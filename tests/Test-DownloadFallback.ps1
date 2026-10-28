# Fixture downloads only. No real network or installer execution.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
foreach($name in 'Confirm-DssDownload','Get-DssPackageFromWeb'){
 $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
 . ([scriptblock]::Create($node.Extent.Text))
}
$root=Join-Path $env:TEMP ('DSC-Fallback-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
 $script:Pass=0
 function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:Pass++;Write-Host "PASS: $message"}
 function Say{param($a,$b)}
 function Write-DscEvent{param($a,$b,$c)}
 function Write-DscError{param($a,$b)}
 function Read-DssDownloadApproval{param($message)$script:Asks++;return $true}
 function Get-DownloadsFolder{$root}
 function Test-PackagePath{param($p)@{Kind='zip';Path=$p}}
 function Test-PackageValid{param($p)@{Ok=$true}}
 function Get-WebFileResume{param($url,$out)
  $script:Calls+=$url
  if($url -eq 'https://example.invalid/primary.zip' -and $script:Failure -eq 'network'){return @{Ok=$false;Text='HTTP 502'}}
  if($script:Failure -eq 'all'){return @{Ok=$false;Text='HTTP 403'}}
  if($url -eq 'https://example.invalid/primary.zip' -and $script:Failure -eq 'html'){
   [IO.File]::WriteAllText($out,'<html>Google sign in</html>')
  }else{[IO.File]::WriteAllBytes($out,[byte[]]@(0x50,0x4B,3,4,0,0,0,0))}
  return @{Ok=$true}
 }
 $Cfg=@{DssVersion='4.1.8';AllowDssDownload=$true;PackageUrl='https://example.invalid/primary.zip';PackageFallbackUrl='https://example.invalid/drive.zip';PackageSha256=''}
 $CheckOnly=$false;$TestMode=$false;$script:DiagnosticsOnly=$false;$script:ReviewApproved=$false
 $RunDir=$root;$script:DscSession=@{SessionId='fixture'}
 foreach($scenario in 'network','html'){
  $script:Failure=$scenario;$script:Calls=@();$script:Asks=0;$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
  Assert ((Get-DssPackageFromWeb) -and $script:Calls.Count -eq 2 -and $script:Calls[1] -eq $Cfg.PackageFallbackUrl -and $script:Asks -eq 1) "$scenario primary failure automatically tries validated fallback with one approval"
 }
 $script:Failure='all';$script:Calls=@();$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
 $failed=$false;try{[void](Get-DssPackageFromWeb)}catch{$failed=$true}
 Assert ($failed -and $script:DssPackageFailure -match 'HTTP 403' -and $script:DssPackageFailure -match 'primary.zip' -and $script:DssPackageFailure -match 'drive.zip') 'both failed sources retain specific failure reasons'
 $script:Failure='';$script:Calls=@();$script:Asks=0
 $Cfg.PackageFallbackUrl='https://example.invalid/new-drive.zip'
 Assert ((Get-DssPackageFromWeb) -and $script:Asks -eq 1) 'changing fallback invalidates earlier download approval'
 Write-Host "FALLBACK TOTAL PASS: $script:Pass"
} finally {
 # Remove only files created by this uniquely named fixture.
 if($root.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
