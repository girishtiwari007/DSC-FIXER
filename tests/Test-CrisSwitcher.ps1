# Fixtures only: no real processes, installers, browsers, shortcuts or ports are changed.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'troubleshooter.ps1'));$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors);if($errors.Count){throw 'Parse failed'}
$script:Count=0
function Assert-Cris($ok,$label){if(-not $ok){throw "FAIL: $label"};$script:Count++;Write-Host "PASS: $label"}
function Read-CrisFunction($name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"};$n.Extent.Text}
foreach($name in 'Get-CrisCatalog','Get-CrisDefinition','Get-CrisState','Invoke-CrisSwitch','Assert-CrisCoexistence','Install-CrisPlanned','Stop-CrisVerified','Save-CrisDesktopSwitcher'){
 . ([scriptblock]::Create((Read-CrisFunction $name)))
}
$script:Entries=@();$script:Ports=@{2068=@();2039=@()};$script:Exists=$true;$script:Actions=@();$script:Events=@();$script:Cancelled=$false
function Test-Path {param($LiteralPath,$PathType) return $script:Exists}
function Get-CrisProcesses($Exe){@($script:Entries|Where-Object ExecutablePath -eq $Exe)}
function Get-CrisPortPids($Port){@($script:Ports[[int]$Port])}
function Update-Ui{}
function Say{param($message,$color)}
function Write-DscEvent{param($level,$operation,$data)$script:Events+=@{Operation=$operation;Data=$data}}
$catalog=@(Get-CrisCatalog)
Assert-Cris ($catalog.Count -eq 2 -and $catalog[0].Port -eq 2068 -and $catalog[1].Port -eq 2039) 'two exact signer/port definitions'
Assert-Cris ($catalog[0].Exe -eq 'C:\CrisSigner\CrisSigner_IPAS\CrisSigner.exe' -and $catalog[1].Exe -eq 'C:\CrisSigner\CrisSigner_IRWCMS\CrisSigner.exe') 'separate paths match requested shortcut locations'
$threw=$false;try{Get-CrisDefinition Unknown}catch{$threw=$true};Assert-Cris $threw 'unknown signer ID rejected'
Assert-Cris ((Get-CrisState IPAS).State -eq 'STOPPED') 'no process/listener reports stopped'
$script:Exists=$false;Assert-Cris ((Get-CrisState IPAS).State -eq 'NOT INSTALLED AT TARGET') 'missing target is visibly distinct';$script:Exists=$true
$script:Entries=@([pscustomobject]@{ExecutablePath=$catalog[0].Exe;ProcessId=101})
Assert-Cris ((Get-CrisState IPAS).Color -eq 'DarkOrange') 'process without listener is amber'
$script:Ports[2068]=@(101);Assert-Cris ((Get-CrisState IPAS).State -eq 'RUNNING') 'green requires exact executable PID owning expected port'
$script:Ports[2068]=@(999);Assert-Cris ((Get-CrisState IPAS).Conflict) 'unknown port owner reports conflict'
$IsAdmin=$true;$script:CancelRequested=$false
function Stop-CrisVerified($Id){$d=Get-CrisDefinition $Id;$script:Actions+=('stop:'+ $Id);$script:Entries=@($script:Entries|Where-Object ExecutablePath -ne $d.Exe);$script:Ports[$d.Port]=@()}
function Start-Process{param($FilePath,$WorkingDirectory,$ErrorAction,$ArgumentList,[switch]$PassThru)
 if($FilePath -like '*msiexec.exe'){return $script:FakeInstaller}
 $d=Get-CrisCatalog|Where-Object Exe -eq $FilePath;if(-not $d){throw 'Unexpected executable launch'}
 $script:Actions+=('start:'+ $d.Id);$script:Entries+=([pscustomobject]@{ExecutablePath=$FilePath;ProcessId=202});$script:Ports[$d.Port]=@(202)
}
$threw=$false;try{Invoke-CrisSwitch IPAS}catch{$threw=$true};Assert-Cris ($threw -and $script:Actions.Count -eq 0) 'switch blocked without confirmation'
$threw=$false;try{Invoke-CrisSwitch IPAS -Confirmed}catch{$threw=$true};Assert-Cris ($threw -and $script:Actions.Count -eq 0) 'target port conflict blocks switch before stopping anything'
$script:Ports[2068]=@();$script:Entries=@([pscustomobject]@{ExecutablePath=$catalog[1].Exe;ProcessId=301});$script:Ports[2039]=@(301)
Invoke-CrisSwitch IPAS -Confirmed
Assert-Cris (($script:Actions -join ',') -eq 'stop:IRWCMS,start:IPAS') 'switch stops other identified signer before starting target'
Assert-Cris ((Get-CrisState IPAS).State -eq 'RUNNING' -and -not (Get-CrisState IRWCMS).Owners.Count) 'switch result verifies target port and other stopped'
$before=$script:Actions.Count;$IsAdmin=$false;$threw=$false;try{Invoke-CrisSwitch IRWCMS -Confirmed}catch{$threw=$true};Assert-Cris ($threw -and $script:Actions.Count -eq $before) 'non-admin switch cannot change processes';$IsAdmin=$true
$script:CancelRequested=$true;Invoke-CrisSwitch IRWCMS -Confirmed;Assert-Cris ($script:Actions.Count -eq $before) 'cancel before switch prevents process changes';$script:CancelRequested=$false
# Restore the real stop helper and fixture its system boundary.
. ([scriptblock]::Create((Read-CrisFunction 'Stop-CrisVerified')))
$script:Entries=@([pscustomobject]@{ExecutablePath=$catalog[0].Exe;ProcessId=101});$script:Service=$true;$script:Identity=$catalog[0].Exe;$script:Killed=0
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)if($ClassName -eq 'Win32_Service'){if($script:Service){[pscustomobject]@{Name='fixture-service'}}}else{[pscustomobject]@{ExecutablePath=$script:Identity;ProcessId=101}}}
function Get-Process{param($Id,$ErrorAction)throw 'Must not terminate unknown or service-backed process'}
$threw=$false;try{Stop-CrisVerified IPAS}catch{$threw=$true};Assert-Cris $threw 'service-backed signer is blocked before process termination'
$script:Service=$false;$script:Identity='C:\Unrelated\CrisSigner.exe';$threw=$false;try{Stop-CrisVerified IPAS}catch{$threw=$true};Assert-Cris $threw 'PID identity revalidated immediately before stopping'
$a=[pscustomobject]@{Id='IPAS';Path='fixture.msi';ProductCode='{11111111-1111-1111-1111-111111111111}';UpgradeCode='{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}';Directory='INSTALLDIR';SHA256='fixture';Publisher='Fixture Publisher'}
$b=[pscustomobject]@{Id='IRWCMS';ProductCode=$a.ProductCode;UpgradeCode='{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}'}
$threw=$false;try{Assert-CrisCoexistence $a $b}catch{$threw=$true};Assert-Cris $threw 'shared MSI product identity blocks side-by-side installation'
$b.ProductCode='{22222222-2222-2222-2222-222222222222}';$b.UpgradeCode=$a.UpgradeCode
$threw=$false;try{Assert-CrisCoexistence $a $b}catch{$threw=$true};Assert-Cris $threw 'shared upgrade identity also blocks coexistence'
$b.UpgradeCode='{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}';Assert-CrisCoexistence $a $b
Assert-Cris $true 'distinct inspected identities pass coexistence preflight'
$threw=$false;try{Assert-CrisCoexistence $a $null}catch{$threw=$true};Assert-Cris $threw 'both packages required before installation'
function Get-CrisMsiPlan{param($Path,$Id)$a}
function Get-UninstallEntries{@()}
$RunDir='C:\FixtureOnly';$script:FakeInstaller=[pscustomobject]@{ExitCode=3010;Disposed=$false}
$script:FakeInstaller|Add-Member ScriptMethod WaitForExit {param($ms)return $true}
$script:FakeInstaller|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
$threw=$false;try{Install-CrisPlanned $a $b}catch{$threw=$true};Assert-Cris $threw 'MSI execution requires explicit confirmation'
Install-CrisPlanned $a $b -Confirmed
Assert-Cris ($script:FakeInstaller.Disposed -and $script:Events[-1].Data.RebootRequired) 'installer reboot exit retained and process handle disposed'
function Get-UninstallEntries{@([pscustomobject]@{PSChildName=$a.ProductCode;InstallLocation='C:\CrisSigner\CrisSigner'})}
$threw=$false;try{Install-CrisPlanned $a $b -Confirmed}catch{$threw=$true};Assert-Cris $threw 'legacy registered installation blocks unsafe relocation'
function Get-UninstallEntries{@()}
$script:Exists=$false;$threw=$false;try{Install-CrisPlanned $a $b -Confirmed}catch{$threw=$true};Assert-Cris $threw 'installer success without target executable is not reported as validated';$script:Exists=$true
$NativeSourcePath=$null;$threw=$false;try{Save-CrisDesktopSwitcher -Confirmed}catch{$threw=$true};Assert-Cris $threw 'in-memory source cannot create a misleading desktop shortcut'
Assert-Cris ($source -match "'5' \{ Invoke-DscSelection 'crisgui' \}" -and $source -match "'7' \{ return \}") 'Option 5 opens switcher and Option 7 exits'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$gui=Read-CrisFunction 'Start-CrisGui'
$gui=$gui.Replace('[void]$f.ShowDialog()',@'
Assert-Cris ($tabs.TabPages.Count -eq 2 -and $installPage.Text -eq 'Installer / progress') 'actual GUI separates switcher and installer views'
Assert-Cris ($u.Rows.Count -eq 2 -and $u.Choice.Items.Count -eq 2) 'actual GUI exposes both signers only'
Assert-Cris (-not $u.Busy -and -not $u.Cancel.Enabled) 'actual GUI opens idle without starting installation'
Assert-Cris ($u.Progress.Style -eq 'Continuous' -and $u.Log.ReadOnly) 'actual GUI exposes progress and read-only action log'
'@)
. ([scriptblock]::Create($gui));$script:Ui=$null;$script:UiLog=$null;$script:UiStatus=$null;$script:DscSessionDirectory='fixture';Start-CrisGui
Write-Host "CRIS TOTAL PASS: $script:Count"
