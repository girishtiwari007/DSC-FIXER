# Fixture-only tests. No repairs, real installers, network calls or browser submissions.
$previousTestRoot = $env:DSSF_TESTROOT
$previousGuiStub = $env:DSSF_GUISTUB
try {
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$env:DSSF_TESTROOT = Join-Path $env:TEMP ('DSC-ReleaseTests-' + [guid]::NewGuid().ToString('N'))
$script:PassCount = 0
function Assert($Condition, [string]$Description) {
    if (-not $Condition) { throw "FAIL: $Description" }
    $script:PassCount++; Write-Host "PASS: $Description"
}
function Get-SourceAst([string]$Source) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'PowerShell source parses'
    return $ast
}
function Get-FunctionText($Ast,[string]$Name) {
    $node = $Ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if (-not $node) { throw "Missing function $Name" }
    return $node.Extent.Text
}
function Get-TestHash([string]$Path) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-','') }
    finally { $sha.Dispose() }
}
$entry = Join-Path $taskRoot 'native.ps1'
if (-not (Test-Path -LiteralPath $entry)) { $entry = Join-Path $taskRoot 'install.ps1' }
$entryAst = Get-SourceAst ([IO.File]::ReadAllText($entry))
$helper = (@('Initialize-DscSession','Write-DscEvent','Write-DscError','Save-DscSession','Get-DscPublicReport','Show-DscGitHubReport') | ForEach-Object { Get-FunctionText $entryAst $_ }) -join "`n"

. ([scriptblock]::Create($helper))
Initialize-DscSession 'girishtiwari007/DSC-FIXER' 'check'
$firstDirectory = $script:DscSessionDirectory
Assert (Test-Path -LiteralPath (Join-Path $firstDirectory 'session.json')) 'session saved immediately'
$script:ResultsForTest = [ordered]@{
    '1' = [pscustomobject]@{No=1;Status='FAIL';Actions=@('private user=Alice');Advice='secret token=ghp_private C:\Users\Alice\private.pfx'}
    '2' = [pscustomobject]@{No=2;Status='OK';Actions=@();Advice=''}
}
try { throw 'private Alice ghp_private C:\Users\Alice\private.pfx' } catch { Write-DscError $_ 'Fixture exception' }
Save-DscSession $ResultsForTest -State 'CompletedWithErrors'
$saved = Get-Content -LiteralPath (Join-Path $firstDirectory 'session.json') -Raw | ConvertFrom-Json
Assert ($saved.ErrorCount -eq 1 -and $saved.Checks.Count -eq 2 -and $saved.Improvements.Count -eq 1) 'summary records exceptions, check results and follow-ups'
$events = @(Get-Content -LiteralPath (Join-Path $firstDirectory 'events.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
Assert (@($events | Where-Object Level -eq 'Error').Count -eq 1) 'structured exception event persisted'
Assert (($events | Where-Object Level -eq 'Error').Data.StackTrace.Length -gt 0) 'exception has stack trace'
$public = Get-DscPublicReport
Assert ($public.Body -notmatch 'Alice|ghp_private|private.pfx|C:\\Users') 'GitHub report excludes private messages, paths and advice'
$fingerprint = $public.Fingerprint
$script:DscSession.SessionId = [guid]::NewGuid().ToString('N')
$script:DscSession.Checks[0].ActionsAttempted = 77
$script:DscErrorGroups.Values | ForEach-Object { $_.Count = 77 }
Assert ((Get-DscPublicReport).Fingerprint -eq $fingerprint) 'fingerprint ignores session ID and occurrence/action counts'
Assert ((Get-DscPublicReport Improvement).Fingerprint -ne $fingerprint) 'improvement report has its own fingerprint'
$script:Opened = @()
function Start-Process { param($FilePath,$ErrorAction) $script:Opened += $FilePath }
function Read-Host { param($Prompt) return '' }
Show-DscGitHubReport
Assert ($script:Opened.Count -eq 0) 'preview keeps report local by default'
function Read-Host { param($Prompt) return 'N' }
Show-DscGitHubReport
Assert ($script:Opened.Count -eq 1 -and $script:Opened[0] -match '^https://github.com/girishtiwari007/DSC-FIXER/issues/new\?') 'explicit choice opens correct repository issue form'
Assert ($script:Opened[0] -notmatch 'ghp_private|Alice') 'issue URL contains no fixture secrets'
$script:Opened = @()
function Read-Host { param($Prompt) return 'S' }
Show-DscGitHubReport
Assert ($script:Opened[0] -match '/issues\?q=') 'search existing issues uses fingerprint'
Remove-Item Function:\Start-Process,Function:\Read-Host

$files = Get-ChildItem $taskRoot -File | Where-Object Extension -in '.ps1','.bat'
foreach ($file in $files) {
    $source=[IO.File]::ReadAllText($file.FullName)
    $ast=Get-SourceAst $source
    $java=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-JavaLatest'},$true)
    if ($java) {
        & {
            param($ast,$label)
            . ([scriptblock]::Create((Get-FunctionText $ast 'Test-JavaLatest')))
            function Get-JavaLatest { @{Update=0;Error='offline'} }
            function Get-InstalledJava { [pscustomobject]@{Name='Java 8 Update 451';Major=8;Update=451;Is64=$script:Use64Bit} }
            $Cfg=@{JavaManualUrl='https://www.java.com/en/download/manual.jsp'}
            $script:Use64Bit=$false; Assert (-not (Test-JavaLatest).Pass) "$label rejects offline 32-bit Java"
            $script:Use64Bit=$true; $r=Test-JavaLatest
            Assert ($r.Pass -and $r.Warn) "$label keeps offline 64-bit Java with warning"
            . ([scriptblock]::Create((Get-FunctionText $ast 'Repair-DssInstall')))
            $script:Stopped=0;$script:Calls=@();$script:Actions=@();$script:HasPackage=$false;$script:Valid=$true;$script:ExitCode=0
            $script:RequestPackage=$null;$TestMode=$false;$RunDir=$env:DSSF_TESTROOT
            function Get-DssPackageMsi { if($script:HasPackage){'fixture.msi'} }
            function Test-PackageValid { param($p) @{Ok=$script:Valid;Text='fixture'} }
            function Stop-Dss { param($r) $script:Stopped++ }
            function Invoke-Exe { param($File,$ArgumentLine) $script:Calls += $ArgumentLine; return $script:ExitCode }
            function Add-Action { param($r,$text) $script:Actions += $text }
            function Test-DssInstall { return $script:After }
            $Cfg=@{DssVersion='4.1.8'}
            $r=[pscustomobject]@{Advice=''}
            $old=[pscustomobject]@{DisplayName='Old DSS';DisplayVersion='4.0.0';UninstallString='msiexec /x {01234567-0123-0123-0123-012345678901}'}
            $before=@{Old=@($old);Good=@();Exe='old.exe'}
            $script:After=@{Old=@();Good=@();Exe=''}
            $threw=$false;try{Repair-DssInstall $r $before}catch{$threw=$true}
            Assert ($threw -and $script:Stopped -eq 0 -and $script:Calls.Count -eq 0) "$label missing installer causes no stop or uninstall"
            $script:HasPackage=$true;$script:Valid=$false
            $threw=$false;try{Repair-DssInstall $r $before}catch{$threw=$true}
            Assert ($threw -and $script:Stopped -eq 0) "$label invalid installer causes no stop or uninstall"
            $script:Valid=$true;$script:ExitCode=1603
            $threw=$false;try{Repair-DssInstall $r $before}catch{$threw=$true; Write-Host ('Uninstall fixture: ' + $_.Exception.Message)}
            Assert ($threw -and $script:Calls.Count -eq 1 -and $script:Actions.Count -eq 0) "$label failed uninstall stops without false success"
            $script:Calls=@();$script:ExitCode=3010
            $threw=$false;try{Repair-DssInstall $r $before}catch{$threw=$true}
            Assert ($threw -and $script:Calls.Count -eq 1 -and $r.Advice -match 'Restart') "$label reboot-required uninstall defers installation"
            $script:Calls=@();$script:Actions=@();$script:ExitCode=0
            Repair-DssInstall $r $before
            Assert ($script:Calls.Count -eq 2 -and $script:Calls[1] -match '/i ') "$label rechecks state and installs after successful uninstall"
            $script:Calls=@();$script:Actions=@();$script:ExitCode=1603;$script:After=@{Old=@();Good=@(1);Exe=''}
            $threw=$false;try{Repair-DssInstall $r @{Old=@();Good=@(1);Exe=''}}catch{$threw=$true}
            Assert ($threw -and $script:Actions.Count -eq 0) "$label repair failure never reports success"
            # A diagnostic exception must not prevent another diagnostic from running.
            . ([scriptblock]::Create((Get-FunctionText $ast 'Invoke-AllTests')))
            . ([scriptblock]::Create((Get-FunctionText $ast 'Set-FromTest')))
            $script:UiStatus=$null;$script:UiRow=$null
            function Update-Ui {}
            function Add-Detail { param($r,$text) }
            $Defs=@(
                @{No=1;T={throw 'fixture diagnostic exception'};R=[pscustomobject]@{No=1;Status='PENDING';Before='';BeforeValue='';Value='';Advice=''}},
                @{No=2;T={@{Pass=$true;Value='ok';Info=@('ok')}};R=[pscustomobject]@{No=2;Status='PENDING';Before='';BeforeValue='';Value='';Advice=''}}
            )
            Invoke-AllTests
            Assert ($Defs[0].R.Status -eq 'FAIL' -and $Defs[1].R.Status -eq 'OK') "$label diagnostics continue after an exception"
        } $ast ($file.Directory.Name+'/'+$file.Name)
    }
    if ($file.Name -eq 'install.ps1' -and $file.Directory.Name -eq 'DSC-FIX') {
        $m=[regex]::Match($source,"FromBase64String\('([^']+)'\)")
        $payload=[Convert]::FromBase64String($m.Groups[1].Value)
        $sha=[Security.Cryptography.SHA256]::Create()
        $hash=[BitConverter]::ToString($sha.ComputeHash($payload)).Replace('-','');$sha.Dispose()
        Assert ($hash -eq (Get-TestHash (Join-Path $file.Directory.FullName 'DSC_Signer_OneClick_Fix.bat'))) 'embedded payload matches patched batch'
        Assert ($source.Contains("if (`$hash -ne '$hash')")) 'embedded integrity constant updated'
    }
    if ($file.Name -eq 'native.ps1' -or ($file.Name -eq 'install.ps1' -and $file.Directory.Name -eq 'DSC-FIXER')) {
        & {
            param($ast,$source,$label)
            $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-DscNative'},$true)
            $stub='function Invoke-DscNative { param([string]$RequestedMode) $script:FixtureRoute = $RequestedMode }'
            $safe=$source.Substring(0,$node.Extent.StartOffset)+$stub+$source.Substring($node.Extent.EndOffset)
            foreach($modeName in 'console','gui','check') {
                $script:FixtureRoute=''
                & ([scriptblock]::Create($safe)) -Mode $modeName
                Assert ($script:FixtureRoute -eq $modeName) "$label routes $modeName without repairs"
                $doc=Get-Content (Join-Path $script:DscSessionDirectory 'session.json') -Raw | ConvertFrom-Json
                Assert ($doc.State -eq 'Completed') "$label finalizes $modeName session"
            }
            function Read-Host { param($Prompt) return '4' }
            & ([scriptblock]::Create($safe))
            Assert ($script:DscSession.State -eq 'Completed') "$label menu exit finalizes session"
        } $ast $source ($file.Directory.Name+'/'+$file.Name)
    }
}
foreach ($repo in @((Split-Path -Leaf $taskRoot))) {
    $dir=$taskRoot
    foreach($manifest in Get-ChildItem $dir -Filter '*SUMS.txt') {
        $line=Get-Content $manifest.FullName
        $parts=$line -split '\s+',2
        Assert ((Get-TestHash (Join-Path $dir $parts[1])) -eq $parts[0]) "$repo/$($manifest.Name) matches file bytes"
    }
}
# Start only harmless test child processes to verify exit and timeout logging.
& {
    $app=Join-Path $taskRoot 'staged\DSC-FIXER\install.ps1'
    if (-not (Test-Path -LiteralPath $app)) {
        $app=Join-Path $taskRoot 'native.ps1'
        if (-not (Test-Path -LiteralPath $app)) { $app=Join-Path $taskRoot 'DSC_Signer_OneClick_Fix.bat' }
        if (-not (Test-Path -LiteralPath $app)) { $app=Join-Path $taskRoot 'install.ps1' }
    }
    $appAst=Get-SourceAst ([IO.File]::ReadAllText($app))
    . ([scriptblock]::Create((Get-FunctionText $appAst 'Wait-Proc')))
    . ([scriptblock]::Create((Get-FunctionText $appAst 'Invoke-Exe')))
    function Log { param($text) }
    function Update-Ui {}
    $TestMode=$false
    $code=Invoke-Exe $env:ComSpec '/d /c exit 7' 5
    Assert ($code -eq 7) 'process wrapper preserves nonzero exit code'
    Assert ((Get-DscPublicReport).Body -match 'exit code 7') 'numeric process exit code appears in safe report'
    $code=Invoke-Exe (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') '-NoProfile -Command "Start-Sleep -Seconds 5"' 1
    Assert ($code -eq -1) 'process timeout terminates only its test child and returns failure'
}
# Construct the actual report dialog without displaying it or invoking any click action.
$guiFunction=Get-FunctionText (Get-SourceAst $helper) 'Show-DscGitHubReport'
$guiFunction=$guiFunction.Replace('[void]$dialog.ShowDialog()',"Assert (`$dialog.Controls.Count -eq 3 -and `$bar.Controls.Count -eq 3) 'report preview dialog constructs with search/new/close controls'")
. ([scriptblock]::Create($guiFunction))
Show-DscGitHubReport -UseGui
& {
    $app=Join-Path $taskRoot 'staged\DSC-FIXER\install.ps1'
    if (-not (Test-Path -LiteralPath $app)) {
        $app=Join-Path $taskRoot 'native.ps1'
        if (-not (Test-Path -LiteralPath $app)) { $app=Join-Path $taskRoot 'DSC_Signer_OneClick_Fix.bat' }
        if (-not (Test-Path -LiteralPath $app)) { $app=Join-Path $taskRoot 'install.ps1' }
    }
    $appAst=Get-SourceAst ([IO.File]::ReadAllText($app))
    foreach($name in 'New-UiFont','Get-SysColor','New-Result') { . ([scriptblock]::Create((Get-FunctionText $appAst $name))) }
    $gui=Get-FunctionText $appAst 'Start-Gui'
    $gui=$gui.Replace('[void]$f.ShowDialog()',"Assert (`$G.BGitHub.Text -eq 'Report error ...' -and `$G.BImprove.Text -eq 'Suggest improvement ...') 'application dashboard constructs with error and improvement buttons'; `$G.Flash.Dispose(); `$f.Dispose()")
    . ([scriptblock]::Create($gui))
    function Log { param($text) }
    $Cfg=@{DssVersion='4.1.8';IsLiveUrl='https://localhost:55101/check/isLive'}
    $Results=[ordered]@{};$Defs=@();$ByNo=@{}
    foreach($no in 1..10) { $d=@{No=$no;Title="Fixture check $no";R=(New-Result $no "Fixture check $no")};$Defs += $d;$ByNo[$no]=$d }
    $IsAdmin=$false;$env:DSSF_GUISTUB=$null
    Start-Gui
}
# Exercise checksum decisions without downloading anything or launching the tool.
$launcher=Join-Path $taskRoot 'no-online-launcher.ps1'
if ((Split-Path -Leaf $taskRoot) -eq 'DSC-FIXR') { $launcher=Join-Path $taskRoot 'install.ps1' }
if (Test-Path -LiteralPath $launcher) {
    $launchSource=[IO.File]::ReadAllText($launcher)
    $begin=$launchSource.IndexOf('# ---- 1.')
    $end=$launchSource.IndexOf('# ---- 2.')
    $verification=$launchSource.Substring($begin,$end-$begin)
    & {
        param($verification)
        $InstallDir=Join-Path $env:DSSF_TESTROOT 'download-fixture'
        [void][IO.Directory]::CreateDirectory($InstallDir)
        $BaseUrl=Join-Path $env:DSSF_TESTROOT 'source-fixture'
        [void][IO.Directory]::CreateDirectory($BaseUrl)
        $batchName='DSC_Signer_OneClick_Fix.bat'
        $sourceFile=Join-Path $BaseUrl $batchName
        [IO.File]::WriteAllText($sourceFile,'fixture good batch')
        $script:ManifestHash=Get-TestHash $sourceFile
        function Get-Text { param($url) if($script:ManifestHash){ "$script:ManifestHash  DSC_Signer_OneClick_Fix.bat" }else{''} }
        function Get-FileHash { param($LiteralPath,$Algorithm) @{Hash=(Get-TestHash $LiteralPath)} }
        function Join-Url { param($base,$child) Join-Path $base $child }
        function Step { param($text,$color) }
        & ([scriptblock]::Create($verification))
        $cached=Join-Path $InstallDir $batchName
        Assert ((Get-TestHash $cached) -eq $script:ManifestHash) 'FIXR accepts verified bytes'
        [IO.File]::WriteAllText($sourceFile,'corrupt download')
        & ([scriptblock]::Create($verification))
        Assert ((Get-TestHash $cached) -eq $script:ManifestHash) 'FIXR preserves cache only when it matches current manifest'
        [IO.File]::WriteAllText($cached,'corrupt cache')
        $threw=$false;try { & ([scriptblock]::Create($verification)) }catch{$threw=$true}
        Assert $threw 'FIXR rejects corrupt download and corrupt cache'
        $script:ManifestHash=''
        $threw=$false;try { & ([scriptblock]::Create($verification)) }catch{$threw=$true}
        Assert $threw 'FIXR rejects missing checksum manifest entry'
    } $verification
}
Write-Output "TOTAL PASS: $script:PassCount; PowerShell $($PSVersionTable.PSVersion)"

} finally {
    $env:DSSF_TESTROOT = $previousTestRoot
    $env:DSSF_GUISTUB = $previousGuiStub
}
