# Isolated one-click sequence fixtures. Never installs, uninstalls, or changes shortcuts.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'install.ps1'));$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e);if($e.Count){throw 'Source parse failed'}
$script:Pass=0
function Assert-Setup($ok,$name){if(-not $ok){throw "FAIL: $name"};$script:Pass++;Write-Host "PASS: $name"}
foreach($name in 'Get-CrisKnownPackages','Test-CrisKnownPackage','Get-CrisCatalog','Get-CrisDefinition','Get-CrisExistingProducts','Assert-CrisCoexistence','Invoke-CrisSetupBoth'){
 $n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"};. ([scriptblock]::Create($n.Extent.Text))
}
$known=Get-CrisKnownPackages
Assert-Setup (Test-CrisKnownPackage IPAS $known.IPAS.Hash $known.IPAS.Product $known.IPAS.Upgrade) 'inspected unsigned IPAS copy accepted only at exact identity/hash'
Assert-Setup (-not (Test-CrisKnownPackage IPAS 'changed' $known.IPAS.Product $known.IPAS.Upgrade)) 'changed unsigned package rejected'
Assert-Setup (-not (Test-CrisKnownPackage IRWCMS $known.IPAS.Hash $known.IPAS.Product $known.IPAS.Upgrade)) 'IPAS package cannot be mislabeled as IRWCMS'
$script:Apps=@([pscustomobject]@{DisplayName='CrisSigner';PSChildName=$known.IPAS.Product;DisplayVersion='1.4.0';InstallLocation='C:\CrisSigner'})
function Get-UninstallEntries{$script:Apps}
Assert-Setup (@(Get-CrisExistingProducts).Count -eq 1) 'existing CRIS MSI recognized by exact application name and GUID'
$script:Apps+=([pscustomobject]@{DisplayName='Digital Signer Service';PSChildName=$known.IRWCMS.Product})
Assert-Setup (@(Get-CrisExistingProducts).Count -eq 1) 'unrelated signer application is excluded from uninstall inventory'
$script:Apps=@([pscustomobject]@{DisplayName='CrisSigner';PSChildName='unknown-uninstaller'})
$blocked=$false;try{Get-CrisExistingProducts}catch{$blocked=$true};Assert-Setup $blocked 'non-MSI CRIS uninstall cannot run an arbitrary command string'
$RunDir=Join-Path $env:TEMP ('CrisSetupFixture-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($RunDir)
$IsAdmin=$true;$script:CrisUi=@{Progress=[pscustomobject]@{Value=0}};$script:Actions=@();$script:CancelRequested=$false;$script:FailDownload=$false;$script:FailTransform=$false;$script:Reboot=$false;$script:Missing=$false
function Reset-SetupFixture{
 $script:Actions=@();$script:Apps=@();$script:FailDownload=$false;$script:FailTransform=$false;$script:Reboot=$false;$script:Missing=$false;$script:CancelRequested=$false
}
function Get-CrisSetupPackage($Id){$script:Actions+=('download:'+ $Id);if($script:FailDownload -and $Id -eq 'IRWCMS'){throw 'Fixture second download failed'};$k=(Get-CrisKnownPackages)[$Id];[pscustomobject]@{Id=$Id;Path=($Id+'.msi');SHA256=$k.Hash;ProductCode=$k.Product;UpgradeCode=$k.Upgrade}}
function New-CrisFolderTransform($Plan){$script:Actions+=('transform:'+ $Plan.Id);if($script:FailTransform -and $Plan.Id -eq 'IRWCMS'){throw 'Fixture transform failed'};return ($Plan.Id+'.mst')}
function Test-Path{param($LiteralPath,$PathType)if($LiteralPath -like '*.exe'){return (-not $script:Missing)};return $false}
function Get-Item{param($LiteralPath,$Force)$size=if($LiteralPath -like '*CrisSigner_IPAS*'){805480}else{805856};[pscustomobject]@{Length=$size;Attributes=[IO.FileAttributes]::Normal}}
function Stop-CrisVerified($Id){$script:Actions+=('stop:'+ $Id)}
function Stop-CrisLegacyProcess{$script:Actions+='stop:legacy'}
function Get-FileHash{param($LiteralPath)((Get-CrisKnownPackages)[$LiteralPath.Split('.')[0]])|ForEach-Object{[pscustomobject]@{Hash=$_.Hash}}}
function Invoke-CrisMsiWait($Arguments,$Operation){
 $script:Actions+=$Operation
 if($Operation -like 'Remove existing*'){$script:Apps=@();if($script:Reboot){return 3010}}
 if($Operation -like 'Install *'){
  if($Arguments -notlike '*APPDIR="C:\CrisSigner\"*' -or $Arguments -notlike '*TRANSFORMS=*'){throw 'Directory transform arguments missing'}
 }
 return 0
}
function New-CrisSignerShortcuts{$script:Actions+='shortcuts'}
function Save-CrisDesktopSwitcher{param([switch]$Confirmed)if(-not $Confirmed){throw 'Approval missing'};$script:Actions+='desktop'}
function Invoke-CrisSwitch{param($Id,[switch]$Confirmed)$script:Actions+=('verify:'+ $Id)}
function Say{param($message,$color)}
function Write-DscEvent{param($level,$operation,$data)}
Reset-SetupFixture
$blocked=$false;try{Invoke-CrisSetupBoth}catch{$blocked=$true};Assert-Setup ($blocked -and $script:Actions.Count -eq 0) 'setup blocked without explicit approval'
$IsAdmin=$false;$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true};Assert-Setup ($blocked -and $script:Actions.Count -eq 0) 'setup blocked before download/mutation without admin';$IsAdmin=$true
Reset-SetupFixture;$script:FailDownload=$true;$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true}
Assert-Setup ($blocked -and -not @($script:Actions|Where-Object{$_ -like 'stop:*' -or $_ -like 'Remove*' -or $_ -like 'Install *'}).Count) 'second package failure never uninstalls or stops an existing signer'
Reset-SetupFixture;$script:FailTransform=$true;$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true}
Assert-Setup ($blocked -and -not @($script:Actions|Where-Object{$_ -like 'stop:*' -or $_ -like 'Remove*' -or $_ -like 'Install *'}).Count) 'both transforms required before destructive operations'
Reset-SetupFixture;$script:Apps=@([pscustomobject]@{DisplayName='CrisSigner';PSChildName=$known.IPAS.Product})
$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true}
Assert-Setup ($blocked -and -not @($script:Actions|Where-Object{$_ -like 'stop:*' -or $_ -like 'Remove*'}).Count) 'new unapproved existing product blocks uninstall before stopping anything'
Reset-SetupFixture;$script:Apps=@([pscustomobject]@{DisplayName='CrisSigner';PSChildName=$known.IPAS.Product})
Invoke-CrisSetupBoth -Confirmed -ApprovedExistingCodes @($known.IPAS.Product)
$state=Get-Content (Join-Path $RunDir 'CRIS-setup-state.json') -Raw|ConvertFrom-Json
Assert-Setup (($script:Actions -join ',') -like 'download:IPAS,download:IRWCMS,transform:IPAS,transform:IRWCMS,stop:IPAS,stop:IRWCMS,stop:legacy,Remove existing CRIS *,Install IPAS,Install IRWCMS,shortcuts,desktop,verify:IPAS,verify:IRWCMS,verify:IPAS') 'validated downloads precede uninstall; IPAS then IRWCMS install, then shortcuts and port verification'
Assert-Setup ($state.Finished -and $state.Installed.Count -eq 2 -and $state.Uninstalled.Count -eq 1) 'journal records both installs and exact removed product'
Assert-Setup ($script:Actions[-1] -eq 'verify:IPAS') 'successful setup leaves IPAS active after verifying both ports'
Reset-SetupFixture;$script:Apps=@([pscustomobject]@{DisplayName='CrisSigner';PSChildName=$known.IPAS.Product});$script:Reboot=$true
$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed -ApprovedExistingCodes @($known.IPAS.Product)}catch{$blocked=$true}
$state=Get-Content (Join-Path $RunDir 'CRIS-setup-state.json') -Raw|ConvertFrom-Json
Assert-Setup ($blocked -and $state.RebootRequired -and -not $state.Finished -and -not @($script:Actions|Where-Object{$_ -like 'Install *'}).Count) 'reboot-required uninstall stops before either new installation'
Reset-SetupFixture;$script:Missing=$true;$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true}
Assert-Setup ($blocked -and $script:Actions -notcontains 'shortcuts') 'missing target executable blocks shortcuts and success'
Reset-SetupFixture;$script:CancelRequested=$true;$blocked=$false;try{Invoke-CrisSetupBoth -Confirmed}catch{$blocked=$true}
Assert-Setup ($blocked -and $script:Actions.Count -eq 0) 'cancellation before preflight performs no download or mutation'
# Build actual GUI and verify the simplified default view, without showing it.
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Start-CrisGui'},$true)
$gui=$n.Extent.Text.Replace('[void]$f.ShowDialog()',@'
Assert-Setup ($u.Setup.Text -match 'BOTH' -and $u.Setup.Height -ge 40) 'actual installer view exposes one primary setup action'
Assert-Setup (-not $u.Advanced.Checked) 'manual inspection controls are optional and collapsed by default'
'@)
. ([scriptblock]::Create($gui));$script:Ui=$null;$script:UiLog=$null;$script:UiStatus=$null;$script:DscSessionDirectory='fixture';Start-CrisGui
Write-Host "CRIS SETUP TOTAL PASS: $script:Pass"
