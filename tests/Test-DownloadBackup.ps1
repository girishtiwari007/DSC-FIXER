# Isolated fixtures: no network, installed application changes or real installer execution.
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
$fixtureRoot=Join-Path $env:TEMP ('DSC-DownloadBackup-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$script:DownloadBackupPass=0
function Assert-DownloadBackup($condition,[string]$text){if(-not $condition){throw "FAIL: $text"};$script:DownloadBackupPass++;Write-Host "PASS: $text"}
function Read-DownloadFunction($ast,[string]$name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"};$n.Extent.Text}
foreach($file in (Get-ChildItem $repositoryRoot -File | Where-Object Extension -in '.ps1','.bat')){
 $source=[IO.File]::ReadAllText($file.FullName);$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
 if(-not $ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Confirm-DssDownload'},$true)){continue}
 & {
  param($ast,$source,$label,$fixtureRoot)
  foreach($name in 'Read-DssDownloadApproval','Confirm-DssDownload','Get-DssSha256','Expand-DssArchive','Get-DssPackageFromWeb','Get-DssPackageMsi','Start-DssPackageRequest','Repair-DssInstall'){
   . ([scriptblock]::Create((Read-DownloadFunction $ast $name)))
  }
  function Say{param($text,$color)}
  function Log{param($text)}
  function Update-Ui{}
  function Write-DscEvent{param($level,$operation,$data)}
  function Add-Action{param($r,$text)}
  $Mode='console';$CheckOnly=$false;$TestMode=$false
  $Cfg=@{DssVersion='4.1.8';AllowDssDownload=$true;PackageUrl='https://example.invalid/fixture.zip';PackageSha256='';DssExePaths=@()}
  $script:DiagnosticsOnly=$false;$script:ReviewApproved=$false;$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
  function Ask{param($message,$valid,$default)$default}
  Assert-DownloadBackup (-not (Confirm-DssDownload)) "$label default console permission is No"
  $script:Approvals=0;$script:Approve=$true
  function Read-DssDownloadApproval{param($message)$script:Approvals++;return $script:Approve}
  $script:DssDownloadConsent='NotAsked';$script:DiagnosticsOnly=$true
  Assert-DownloadBackup (-not (Confirm-DssDownload) -and $script:Approvals -eq 0) "$label diagnostics never opens a download permission prompt"
  $script:DiagnosticsOnly=$false;$CheckOnly=$true
  Assert-DownloadBackup (-not (Confirm-DssDownload) -and $script:Approvals -eq 0) "$label check-only cannot download or ask permission"
  $CheckOnly=$false
  Assert-DownloadBackup ((Confirm-DssDownload) -and $script:Approvals -eq 1) "$label explicit review asks permission before download"
  Assert-DownloadBackup ((Confirm-DssDownload) -and $script:Approvals -eq 1) "$label same approved source reuses consent during one operation"
  $Cfg.PackageUrl='https://example.invalid/changed-source.zip'
  Assert-DownloadBackup ((Confirm-DssDownload) -and $script:Approvals -eq 2) "$label changed source requires new permission"
  Assert-DownloadBackup ($source.Contains('[Windows.Forms.MessageBoxDefaultButton]::Button2')) "$label GUI permission defaults to No"
  Assert-DownloadBackup ($source.Contains("AllowDssDownload    = `$true") -and $source.Contains("PackageUrl          = 'https://nr.indianrailways.gov.in/")) "$label download-permission feature is configured in this edition"
  Assert-DownloadBackup ($source.Contains("if(`$env:DSSF_NO_PACKAGE -eq '1')")) "$label explicit download opt-out remains available"

  $work=Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($work);$RunDir=$work
  $script:DscSession=@{SessionId=[guid]::NewGuid().ToString('N')}
  $zipSource=Join-Path $work 'fixture-input';[void][IO.Directory]::CreateDirectory((Join-Path $zipSource 'nested'))
  [IO.File]::WriteAllText((Join-Path $zipSource 'nested\Digital Signer Service 4.1.8.msi'),'fixture MSI bytes')
  $fixtureZip=Join-Path $work 'fixture.zip'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($zipSource,$fixtureZip)
  $script:FixtureZip=$fixtureZip;$script:Downloads=0;$script:Validations=0;$script:PkgOverride=$null;$script:PkgMsi=$null
  function Get-DownloadsFolder{Join-Path $RunDir 'Downloads'}
  function Get-WebFileResume{param($url,$outFile)$script:Downloads++;Copy-Item -LiteralPath $script:FixtureZip -Destination $outFile -Force;@{Ok=$true}}
  function Test-PackagePath{param($p)@{Kind='zip';Path=$p;Version='4.1.8';Text='fixture archive'}}
  function Test-PackageValid{param($p)$script:Validations++;@{Ok=($p -notmatch 'invalid');Text='fixture content/version validation'}}
  function Find-DssPackageSource{if($script:PkgOverride){@{Kind='zip';Path=$script:PkgOverride}}}
  function Find-InFolder{param($path)$msi=Get-ChildItem -LiteralPath $path -Recurse -File -Filter *.msi | Select-Object -First 1;if($msi){@{Kind='msi';Path=$msi.FullName;Version='4.1.8'}}}
  $script:Approve=$false;$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
  $mapped=Get-DssPackageMsi
  Assert-DownloadBackup (-not $mapped -and $script:Downloads -eq 0) "$label declining permission creates no download or mapped installer"
  $script:RequestPackage={throw 'Local ZIP/MSI/folder dialog must not open after declined download.'}
  $stopped=0;function Stop-Dss{param($r)$script:Stopped++};$script:Stopped=0
  $result=[pscustomobject]@{Advice=''};$threw=$false
  try{Repair-DssInstall $result @{Old=@();Good=@();Exe=''}}catch{$threw=$true}
  Assert-DownloadBackup ($threw -and $script:Stopped -eq 0 -and $script:Downloads -eq 0) "$label declined download never opens mapping fallback or changes DSS"
  $script:Approve=$true;$script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
  $mapped=Get-DssPackageMsi
  Assert-DownloadBackup ($script:Downloads -eq 1 -and (Test-Path -LiteralPath $mapped) -and $mapped.EndsWith('.msi') -and $script:Validations -ge 2) "$label approved ZIP is downloaded, extracted, validated and mapped automatically"
  Assert-DownloadBackup ($script:PkgOverride.StartsWith((Join-Path $RunDir 'Downloads'))) "$label original download is retained under Downloads"
  $script:Approvals=0;[void](Get-DssPackageMsi)
  Assert-DownloadBackup ($script:Approvals -eq 0 -and $script:Downloads -eq 1) "$label validated mapped installer is reused without another download"
  $script:PkgMsi=$null;$script:PkgOverride=Join-Path $work 'invalid-old-package.zip'
  $script:DssDownloadConsent='NotAsked';$script:DssDownloadConsentKey=''
  $replacement=Get-DssPackageMsi
  Assert-DownloadBackup ($script:Downloads -eq 2 -and (Test-Path -LiteralPath $replacement)) "$label invalid old package is replaced through permission/download rather than manual mapping"
  $unsafe=Join-Path $work 'unsafe.zip';$unsafeArchive=[IO.Compression.ZipFile]::Open($unsafe,[IO.Compression.ZipArchiveMode]::Create)
  try{$entry=$unsafeArchive.CreateEntry('../escaped.msi');$stream=$entry.Open();try{$stream.WriteByte(1)}finally{$stream.Dispose()}}finally{$unsafeArchive.Dispose()}
  $unsafeBlocked=$false;try{Expand-DssArchive -LiteralPath $unsafe -DestinationPath (Join-Path $work 'unsafe-output')}catch{$unsafeBlocked=$true}
  Assert-DownloadBackup ($unsafeBlocked -and -not (Test-Path -LiteralPath (Join-Path $work 'escaped.msi'))) "$label automatic extraction rejects archive path traversal"

  # Repository backups are a developer workflow, not a prerequisite on user PCs.
  Assert-DownloadBackup ($source -notmatch 'function Backup-DssInstallation') "$label contains no user installation backup function"
  Assert-DownloadBackup ($source -notmatch 'installation-backups') "$label never creates a user installation snapshot folder"
  $script:Stopped=0;$script:Executions=0
  function Get-DssPackageMsi {'approved-installer.msi'}
  function Test-PackageValid {param($p)@{Ok=$true;Text='fixture valid'}}
  function Test-DssInstall {@{Old=@();Good=@();Exe=''}}
  function Stop-Dss {param($r)$script:Stopped++}
  function Invoke-Exe {param($file,$arguments)$script:Executions++;return 0}
  $old=[pscustomobject]@{DisplayName='Old DSS';DisplayVersion='4.0.0';UninstallString='msiexec /x {01234567-0123-0123-0123-012345678901}'}
  & {
   function Copy-Item {throw 'A user-side installation backup must not be attempted.'}
   function Get-DssEntries {throw 'A user-side backup registration snapshot must not be attempted.'}
   Repair-DssInstall $result @{Old=@($old);Good=@();Exe='old.exe'}
  }
  Assert-DownloadBackup ($script:Stopped -eq 1 -and $script:Executions -eq 2) "$label validated repair proceeds without a user-side backup prerequisite"
  $policy=[IO.File]::ReadAllText((Join-Path $repositoryRoot 'AGENTS.md'))
  Assert-DownloadBackup ($policy -match 'timestamped backup' -and $policy -match 'repository' -and $policy -notmatch 'require a fresh verified installation backup') "$label retains repository-file backup policy only"
 } $ast $source $file.Name $fixtureRoot
}
Write-Host "DOWNLOAD BACKUP TOTAL PASS: $script:DownloadBackupPass; PowerShell $($PSVersionTable.PSVersion)"
