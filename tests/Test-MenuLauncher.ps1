# Fixture-only launcher tests. No actual downloads, browsers, GUI windows or repairs.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$path=Join-Path $repo 'install.ps1';$text=[IO.File]::ReadAllText($path)
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Launcher syntax failed'}
$script:LauncherPass=0
function Assert-Launcher($ok,$message){if(-not $ok){throw "FAIL: $message"};$script:LauncherPass++;Write-Host "PASS: $message"}
function Launcher-Function($name){$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);if(-not $node){throw "Missing $name"};$node.Extent.Text}
$engine=Join-Path $repo 'troubleshooter.ps1'
$expected=(Get-FileHash -LiteralPath $engine).Hash
Assert-Launcher ($text.Contains("`$script:DscLauncherHash='$expected'")) 'launcher pins the exact current engine bytes'
Assert-Launcher ((Get-Item $path).Length -lt ((Get-Item $engine).Length/10)) 'initial menu download is less than one tenth of the engine'
Assert-Launcher ($text -notmatch 'function Start-Gui|function Start-CrisGui|Add-Type -AssemblyName System.Windows.Forms') 'initial launcher contains no GUI implementation or WinForms initialization'
$savedLocal=$env:LOCALAPPDATA;$savedTemp=$env:TEMP
$fixture=Join-Path $env:TEMP ('DscMenuTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try{
 $env:LOCALAPPDATA=$fixture;$env:TEMP=$fixture
 $safe=$text.Replace((Launcher-Function 'Get-DscLauncherEngine'),'function Get-DscLauncherEngine {$script:EngineFetches++;if($script:FailLoad){throw "Fixture network failure"};return "fixture engine"}')
 $safe=$safe.Replace((Launcher-Function 'Invoke-DscSelectedEngine'),'function Invoke-DscSelectedEngine {param($Text,$Selection)$script:Routes+= $Selection}')
 function Read-Host {param($Prompt)if(-not $script:Choices.Count){throw 'Unexpected menu loop'};$script:Choices.Dequeue()}
 foreach($case in @(
  @{Choices=@('4','7');Modes=@()},
  @{Choices=@('1','2','3','5','6','7');Modes=@('console','gui','othergui','crisgui','apargui')},
  @{Choices=@('invalid','7');Modes=@()}
 )){
  $script:Choices=New-Object 'Collections.Generic.Queue[string]';foreach($c in $case.Choices){$script:Choices.Enqueue($c)}
  $script:Routes=@();$script:EngineFetches=0;$script:FailLoad=$false
  & ([scriptblock]::Create($safe))
  Assert-Launcher (($script:Routes -join ',') -eq ($case.Modes -join ',')) ('menu routes only selected modes: '+($case.Choices -join ','))
  Assert-Launcher ($script:EngineFetches -eq $case.Modes.Count) 'refresh, invalid choice and exit do not fetch troubleshooting code'
 }
 $script:Routes=@();$script:EngineFetches=0
 & ([scriptblock]::Create($safe)) -Mode apargui
 Assert-Launcher ($script:EngineFetches -eq 1 -and $script:Routes.Count -eq 1 -and $script:Routes[0] -eq 'apargui') 'direct apargui argument preserves APAR routing through lazy loading'
 $script:Routes=@();$script:EngineFetches=0; & ([scriptblock]::Create($safe)) -Mode crisswitch
 Assert-Launcher ($script:EngineFetches -eq 1 -and $script:Routes.Count -eq 1 -and $script:Routes[0] -eq 'crisswitch') 'desktop switcher mode routes through lazy loading'
 $script:Choices=New-Object 'Collections.Generic.Queue[string]';$script:Choices.Enqueue('6');$script:Choices.Enqueue('7')
 $script:Routes=@();$script:FailLoad=$true
 & ([scriptblock]::Create($safe))
 Assert-Launcher ($script:Routes.Count -eq 0) 'failed engine load opens no GUI and permits exit'
 $log=Get-Content -LiteralPath (Join-Path $script:DscLauncherDirectory 'launcher.jsonl') -Raw
 Assert-Launcher ($log -match 'Fixture network failure' -and $log -match 'Launcher closed') 'download error and launcher closure are logged locally'
 foreach($name in 'Write-DscLauncherEvent','Get-DscLauncherHash','Get-DscLauncherEngine','Invoke-DscSelectedEngine'){
  . ([scriptblock]::Create((Launcher-Function $name)))
 }
 $script:DscLauncherRoot=$null;$script:DscLauncherCache=$null;$script:NetworkCalls=0
 $script:FixtureBytes=[Text.Encoding]::UTF8.GetBytes('& { param([string]$Mode) $script:ActualSelectedMode=$Mode } @args')
 function Get-DscLauncherDownload {$script:NetworkCalls++;return ,$script:FixtureBytes}
 $script:DscLauncherHash=Get-DscLauncherHash $script:FixtureBytes
 $first=Get-DscLauncherEngine;$second=Get-DscLauncherEngine
 Assert-Launcher ($first -eq $second -and $script:NetworkCalls -eq 1) 'verified engine is reused in memory without another download'
 Invoke-DscSelectedEngine $first 'apargui'
 Assert-Launcher ($script:ActualSelectedMode -eq 'apargui') 'real scriptblock execution forwards only the selected mode'
 $script:DscLauncherCache=$null;$script:DscLauncherHash='wrong';$blocked=$false
 try{Get-DscLauncherEngine}catch{$blocked=$true}
 Assert-Launcher ($blocked -and -not $script:DscLauncherCache) 'hash mismatch is rejected before caching or execution'
 $script:FixtureBytes=[Text.Encoding]::UTF8.GetBytes('function {');$script:DscLauncherHash=Get-DscLauncherHash $script:FixtureBytes;$blocked=$false
 try{Get-DscLauncherEngine}catch{$blocked=$true}
 Assert-Launcher ($blocked -and -not $script:DscLauncherCache) 'invalid engine syntax is rejected before execution'
 $script:DscLauncherRoot=$repo;$script:DscLauncherHash=$expected;$script:DscLauncherCache=$null;$script:NetworkCalls=0
 $local=Get-DscLauncherEngine
 Assert-Launcher ($local.Contains('function Invoke-DscNative') -and $script:NetworkCalls -eq 0) 'matching checked-out engine runs locally without network access'
}finally{
 $env:LOCALAPPDATA=$savedLocal;$env:TEMP=$savedTemp
 Remove-Item -LiteralPath $fixture -Recurse -Force
}
Write-Host "MENU LAUNCHER TOTAL PASS: $script:LauncherPass"
