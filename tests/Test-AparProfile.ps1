# Fixtures and optional read-only package inspection. No repairs or installers are executed.
param([string]$InspectMsi='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'troubleshooter.ps1'))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Source parsing failed'}
function Import-AparFunction($name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"}; . ([scriptblock]::Create('function script:'+$n.Extent.Text.Substring(9)))}
foreach($name in 'Set-DssProfile','Test-IsDssProcess','Test-IsOtherDssProcess','Test-DscLiveResponse','Test-DssInstall','Repair-DssInstall','Test-Port','Repair-Port','Get-DssMsiProperties','Get-DssSha256','Assert-AparMsiIdentity','Get-DssMsiRelatedVersions','Assert-DssMsiCoexistence','Get-AparBundledJava','Test-JavaLatest','Test-JavaWorks','New-DscBookmarkImportFile','Assert-DssPeerPreserved'){Import-AparFunction $name}
$script:Pass=0
function Assert($ok,$label){if(-not $ok){throw "FAIL: $label"};$script:Pass++;Write-Host "PASS: $label"}
function Must-Throw($body,$label){$failed=$false;try{& $body}catch{$failed=$true};Assert $failed $label}

$dispatch=$ast.Find({param($node)
 $node -is [Management.Automation.Language.IfStatementAst] -and
 $node.Clauses[0].Item1.Extent.Text -like '*$RequestedMode*' -and
 $node.Extent.Text -match '\{ Start-CrisGui \}'
},$true)
Assert ([bool]$dispatch) 'actual native GUI dispatch statement is found'
function Start-CrisGui {$script:OpenedWindow='CRIS'}
function Start-OtherGui {$script:OpenedWindow='Other'}
function Start-Gui {$script:OpenedWindow='DSS'}
function Start-Console {$script:OpenedWindow='Console'}
foreach($case in @(
 @{Requested='apargui';UiMode='gui';Expected='DSS'},
 @{Requested='gui';UiMode='gui';Expected='DSS'},
 @{Requested='crisgui';UiMode='gui';Expected='CRIS'},
 @{Requested='crisinstall';UiMode='gui';Expected='CRIS'},
 @{Requested='crisswitch';UiMode='gui';Expected='CRIS'},
 @{Requested='othergui';UiMode='gui';Expected='Other'},
 @{Requested='console';UiMode='console';Expected='Console'}
)) {
 $RequestedMode=$case.Requested;$Mode=$case.UiMode;$script:OpenedWindow=''
 & ([scriptblock]::Create($dispatch.Extent.Text))
 Assert ($script:OpenedWindow -eq $case.Expected) ("actual dispatch routes "+$case.Requested+" to "+$case.Expected)
}

function Write-DscEvent{param($a,$b,$c)}
function Write-DscError{param($a,$b)throw "Unexpected error: $b $a"}
function Add-Action{param($a,$b)}
function Say{param($a,$b)}
$Cfg=[ordered]@{DssVersion='4.1.8';Port=55101;SignerHost='eoffsigner.eoffice.gov.in';EditionName='E-Office';PackageUrl='original';PackageFallbackUrl='fallback';PackageSha256=''}
Set-DssProfile $Cfg gui
Assert ($Cfg.Port -eq 55101 -and $Cfg.PackageUrl -eq 'original') 'default profile retains E-Office source and port'
Set-DssProfile $Cfg apargui
$Cfg.DssExePaths=@($Cfg.RequiredDssPath)
Assert ($Cfg.DssVersion -eq '7.0.2' -and $Cfg.Port -eq 55103 -and $Cfg.EditionName -match 'APAR') 'APAR selects version, port and GUI identity'
Assert ($Cfg.RequiredDssPath -eq 'C:\Program Files\Digital Signer Service\7.0.2\Digital Signer Service.exe') 'APAR targets a separate versioned directory'
Assert ($Cfg.IsLiveUrl -eq 'https://eoffsigner.eoffice.gov.in:55103/check/isLive') 'APAR endpoint uses 55103'
if(-not ('DssfHttpV3' -as [type])){
 $begin=$source.IndexOf('using System;');$end=$source.IndexOf("`n'@",$begin)
 Add-Type -TypeDefinition $source.Substring($begin,$end-$begin)
}
$now=[DateTime]::UtcNow;$errors=[Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors
$flags=[Security.Cryptography.X509Certificates.X509ChainStatusFlags[]]@('NotTimeValid')
Assert ([DssfHttpV3]::IsExpiryOnly($Cfg.IsLiveUrl,$errors,$flags,[DateTime[]]@($now.AddYears(-1)),[DateTime[]]@($now.AddDays(-1)),$now)) 'APAR accepts only the existing scoped expiry-only exception'
Assert (-not [DssfHttpV3]::IsExpiryOnly('https://eoffsigner.eoffice.gov.in:55104/check/isLive',$errors,$flags,[DateTime[]]@($now.AddYears(-1)),[DateTime[]]@($now.AddDays(-1)),$now)) 'expiry exception excludes other ports'
$flags=[Security.Cryptography.X509Certificates.X509ChainStatusFlags[]]@('NotTimeValid','UntrustedRoot')
Assert (-not [DssfHttpV3]::IsExpiryOnly($Cfg.IsLiveUrl,$errors,$flags,[DateTime[]]@($now.AddYears(-1)),[DateTime[]]@($now.AddDays(-1)),$now)) 'APAR expiry exception does not bypass an untrusted root'
Assert ($Cfg.PackageUrl -eq 'https://drive.usercontent.google.com/download?authuser=0&export=download&id=1X_IpIZjgcjC6A0mvDMef2XJ1vk-iTdpT' -and $Cfg.PackageFallbackUrl -eq ($Cfg.PackageUrl+'&confirm=t')) 'approved Drive URL has same-file large-download confirmation fallback'
Assert ((Test-DscLiveResponse 'success. DSC Signer Service version : 7.0.2') -and -not (Test-DscLiveResponse 'success. DSC Signer Service version : 4.1.8')) 'APAR refuses a successful response from the wrong version'
$own=[pscustomobject]@{Id=1;Name='Digital Signer Service';Path=$Cfg.RequiredDssPath}
$peer=[pscustomobject]@{Id=2;Name='Digital Signer Service';Path='C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe'}
Assert ((Test-IsDssProcess $own) -and -not (Test-IsDssProcess $peer) -and (Test-IsOtherDssProcess $peer)) 'APAR process detection excludes E-Office'
Assert (Test-IsDssProcess @{Name='java';Path='C:\Program Files\Digital Signer Service\7.0.2\jre64\bin\java.exe'}) 'APAR bundled Java listener is recognized'
Assert (-not (Test-IsDssProcess @{Name='CrisSigner';Path='C:\CrisSigner\CrisSigner.exe'})) 'unrelated signer process is excluded'
Assert (-not (Test-IsDssProcess @{Name='Digital Signer Service';Path=''})) 'unknown process path is never assumed safe'
function Get-DssEntries {@(@{DisplayName='Digital Signer Service 4.1.8';DisplayVersion='4.1.8'},@{DisplayName='Digital Signer Service 7.0.2';DisplayVersion='7.0.2'})}
function Get-DssStdExe {$Cfg.RequiredDssPath}
function Get-ExeVersion {param($p)$Cfg.DssVersion}
$state=Test-DssInstall
Assert ($state.Pass -and $state.Old.Count -eq 0 -and $state.Good.Count -eq 1) 'coexisting E-Office does not fail APAR installation check'
$Cfg.DssVersion='4.1.8'
$state=Test-DssInstall
Assert ($state.Pass -and $state.Old.Count -eq 0 -and $state.Good.Count -eq 1) 'coexisting APAR does not fail E-Office installation check'
$Cfg.DssVersion='7.0.2'
function Get-PortListeners {@($peer)}
function Get-ExcludedRanges {@()}
$port=Test-Port
Assert (-not $port.Pass -and $port.Bad.Count -eq 1) 'wrong-version listener is flagged as a port conflict'
$Cfg.KillPortOwners=$true;$TestMode=$false;$script:Stopped=0
function Stop-Process{param($Id,$Force,$ErrorAction)$script:Stopped++}
Must-Throw {Repair-Port @{} $port} 'port repair refuses to stop coexisting E-Office'
Assert ($script:Stopped -eq 0) 'protected port conflict causes no process stop'
function Get-DssMsiRelatedVersions{param($p)@('7.0.2','4.1.8')}
Must-Throw {Assert-DssMsiCoexistence 'fixture.msi'} 'MSI cross-version upgrade relationship blocks APAR installation'
function Get-DssMsiRelatedVersions{param($p)@('7.0.2')}
Assert-DssMsiCoexistence 'fixture.msi'
Assert $true 'same-version MSI relationship is allowed'
$script:Installed=0;$script:Stopped=0
function Get-DssPackageMsi {'fixture.msi'}
function Test-PackageValid {param($p)@{Ok=$true}}
function Stop-Dss {param($r)$script:Stopped++}
function Invoke-Exe {param($p,$args)$script:Installed++;0}
Must-Throw {Repair-DssInstall @{} @{Old=@(@{DisplayVersion='4.1.8';DisplayName='Digital Signer Service'});Good=@();Exe=''}} 'stale uninstall plan cannot remove E-Office'
Assert ($script:Stopped -eq 0 -and $script:Installed -eq 0) 'stale plan is refused before any process or installer mutation'
function Get-DssMsiRelatedVersions{param($p)@('4.1.8')}
Must-Throw {Repair-DssInstall @{} @{Old=@();Good=@();Exe=''}} 'unsafe MSI is rejected through the actual repair entry point'
Assert ($script:Stopped -eq 0 -and $script:Installed -eq 0) 'MSI coexistence guard runs before stop or install'
$tmp=Join-Path $env:TEMP ('DscAparFixture-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp)
try {
 $Cfg.RequiredDssPath=Join-Path $tmp 'Digital Signer Service.exe'
 $java=Join-Path $tmp 'jre64\bin\java.exe';[void][IO.Directory]::CreateDirectory((Split-Path $java));[IO.File]::WriteAllText($java,'fixture only, never executed')
 function Invoke-JavaVersion{param($p)@{Code=0;Text='java version "17.0.1"'}}
 Assert ((Test-JavaLatest).Pass) 'working APAR bundled runtime avoids global Java installation requirement'
 function Find-DssExe {$Cfg.RequiredDssPath}
 Assert ((Test-JavaWorks).Pass) 'APAR Java execution check uses its own bundled runtime'
 function Invoke-JavaVersion{param($p)@{Code=1;Text='corrupt runtime'}}
 Assert (-not (Test-JavaLatest).Pass -and -not (Test-JavaWorks).Pass) 'broken bundled Java is reported instead of accepting global Java'
 $RunDir=$tmp
 $bookmark=New-DscBookmarkImportFile -Confirmed
 Assert ([IO.File]::ReadAllText($bookmark).Contains('https://eoffsigner.eoffice.gov.in:55103/check/isLive')) 'APAR bookmark targets APAR endpoint'
 [IO.File]::WriteAllText((Join-Path $tmp 'changed.exe'),'changed')
 Must-Throw {Assert-DssPeerPreserved @{Hash='before';Path=(Join-Path $tmp 'changed.exe')}} 'peer executable modification fails preservation verification'
} finally {Remove-Item -LiteralPath $tmp -Recurse -Force}
if($InspectMsi){
 $id=Get-DssMsiProperties $InspectMsi
 Assert ($id.ProductVersion -eq '7.0.2' -and $id.ProductCode -eq $Cfg.ProductCode) 'read-only MSI database confirms APAR product identity'
 Assert-AparMsiIdentity $InspectMsi
 Assert $true 'actual downloaded APAR MSI passes signature, hash and identity validation'
 $old=$Cfg.MsiSha256;$Cfg.MsiSha256='wrong'
 Must-Throw {Assert-AparMsiIdentity $InspectMsi} 'changed APAR MSI pin is rejected'
 $Cfg.MsiSha256=$old
}
Assert ($source.Contains("'6' { Invoke-DscSelection 'apargui' }") -and $source.Contains("'7' { return }")) 'menu exposes Option 6 APAR and Option 7 Exit'
Assert ($source.Contains('APAR Signer Service 7.0.2 (Run as Admin)')) 'APAR has a separate startup task identity'
Assert ($source.Contains('REBOOT=ReallySuppress AI_UPGRADE=No')) 'APAR silent install suppresses reboot and vendor upgrade removal'
Write-Host "APAR TOTAL PASS: $script:Pass"
