# Fixture-only tests: never alter Java, browser settings, or install software.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source parse failed'}
$script:Passed=0
function Assert-Other($ok,$name){if(-not $ok){throw "FAIL: $name"};$script:Passed++;Write-Host "PASS: $name"}
function Function-Text($name){$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);if(-not $node){throw "Missing $name"};$node.Extent.Text}
foreach($name in 'Get-OtherWebsiteCatalog','Get-OtherSiteSettingsUrl','Open-OtherWebsiteSettings','Test-OtherJavaWorks','Invoke-OtherJavaRepair','Invoke-OtherJavaChecks'){
 . ([scriptblock]::Create((Function-Text $name)))
}
Assert-Other ((Get-OtherWebsiteCatalog).Count -eq 5) 'exactly five approved website origins'
$blocked=$false;try{Get-OtherSiteSettingsUrl Chrome 'https://unrelated.example'}catch{$blocked=$true};Assert-Other $blocked 'unlisted origin rejected'
$blocked=$false;try{Get-OtherSiteSettingsUrl Safari 'https://ireps.gov.in'}catch{$blocked=$true};Assert-Other $blocked 'unlisted browser rejected'
$chrome=Get-OtherSiteSettingsUrl Chrome 'https://aims.indianrailways.gov.in'
Assert-Other ($chrome -eq 'chrome://settings/content/siteDetails?site=https%3A%2F%2Faims.indianrailways.gov.in') 'Chrome settings encode exact selected origin'
Assert-Other ((Get-OtherSiteSettingsUrl Edge 'https://ireps.gov.in') -like 'edge://settings/content/siteDetails?site=*') 'Edge settings use selected origin'
Assert-Other ((Get-OtherSiteSettingsUrl Firefox 'https://ireps.gov.in') -eq 'about:preferences#privacy') 'Firefox uses guided privacy settings'
$TestMode=$false;$script:CancelRequested=$false;$script:Opened=@();$script:Logged=@()
function Start-Process{param($FilePath,$ArgumentList,$ErrorAction)$script:Opened+=@{Exe=$FilePath;Url=$ArgumentList}}
function Find-Browser($name){[pscustomobject]@{Exe=($name+'.exe')}}
function Say{param($text,$color)}
function Write-DscEvent{param($level,$operation,$data)$script:Logged+=$operation}
function Write-DscError{param($record,$operation)throw "Unexpected fixture error: $operation $record"}
$blocked=$false;try{Open-OtherWebsiteSettings @('Chrome') @('https://ireps.gov.in')}catch{$blocked=$true}
Assert-Other ($blocked -and $script:Opened.Count -eq 0) 'website action blocked without confirmation'
Open-OtherWebsiteSettings @('Chrome','Edge','Firefox') @('https://ireps.gov.in','https://www.ireps.gov.in') -Confirmed
Assert-Other ($script:Opened.Count -eq 5) 'only selected browser/origin settings launched; Firefox once'
Assert-Other (@($script:Logged|Where-Object{$_ -match 'pending user action'}).Count -eq 5) 'settings opened never reported as completed reset'
$before=$script:Opened.Count;$blocked=$false
try{Open-OtherWebsiteSettings @('Chrome') @('https://ireps.gov.in','https://unrelated.example') -Confirmed}catch{$blocked=$true}
Assert-Other ($blocked -and $script:Opened.Count -eq $before) 'whole website selection validated before launching'
$script:CancelRequested=$true;Open-OtherWebsiteSettings @('Chrome') @('https://ireps.gov.in') -Confirmed
Assert-Other ($script:Opened.Count -eq $before) 'cancel prevents further browser launches'
$script:CancelRequested=$false
function Find-JavaOnPath{'fixture-java.exe'}
function Invoke-JavaVersion($exe){@{Code=0;Text='java version "1.8.0_101"'}}
function Find-DssExe{throw 'Option 3 must not inspect or repair bundled DSS Java'}
Assert-Other ((Test-OtherJavaWorks).Pass) 'old working Java accepted without contacting vendor or inspecting DSS'
$Results=@{'5'=@{};'7'=@{};'1'=@{}};$script:EnvRepairs=0;$script:JavaRepairs=0;$IsAdmin=$true
function Test-EnvVars{@{Pass=$false}}
function Repair-EnvVars{param($r,$t)$script:EnvRepairs++}
function Repair-JavaWorks{param($r,$t)$script:JavaRepairs++}
function Update-Ui{}
$blocked=$false;try{Invoke-OtherJavaRepair}catch{$blocked=$true}
Assert-Other ($blocked -and $script:EnvRepairs -eq 0) 'Java repair blocked without explicit approval'
Invoke-OtherJavaRepair -Confirmed
Assert-Other ($script:EnvRepairs -eq 1 -and $script:JavaRepairs -eq 0) 'approved stale environment repair preserves working old Java'
$IsAdmin=$false;$blocked=$false;try{Invoke-OtherJavaRepair -Confirmed}catch{$blocked=$true}
Assert-Other ($blocked -and $script:EnvRepairs -eq 1) 'non-admin Java repair blocked before mutation'
$IsAdmin=$true
function Invoke-JavaVersion($exe){@{Code=1;Text='corrupt fixture'}}
Invoke-OtherJavaRepair -Confirmed
Assert-Other ($script:JavaRepairs -eq 1) 'broken shared Java enters approved repair path'
Assert-Other ($source -match "'3' \{ Invoke-DscSelection 'othergui' \}" -and $source -match "'5' \{ return \}") 'menu Option 3 opens dedicated GUI and Option 5 exits'
# Construct the actual form, inspect defaults, then dispose without showing or repairing.
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$gui=Function-Text 'Start-OtherGui'
$gui=$gui.Replace('[void]$f.ShowDialog()',@'
Assert-Other ($o.Sites.CheckedItems.Count -eq 0) 'actual GUI websites start unchecked'
Assert-Other (@($o.Browsers.Values|Where-Object Checked).Count -eq 0) 'actual GUI browsers start unchecked'
Assert-Other ($f.Text -eq 'Reset Java & setting for other Websites') 'actual GUI uses requested title'
Assert-Other (-not $o.Busy -and -not $o.Cancel.Enabled) 'actual GUI starts idle with cancellation inactive'
Assert-Other ($o.Update.Text -match 'Optional') 'actual GUI Java update is separate and optional'
Assert-Other ($o.Sites.Items.Count -eq 5) 'actual GUI shows only approved origin choices'
'@)
$script:DscSessionDirectory='fixture-only';$script:Ui=$null;$script:UiStatus=$null;$script:UiLog=$null
. ([scriptblock]::Create($gui));Start-OtherGui
Assert-Other ((Function-Text 'Confirm-OtherUi') -match 'MessageBoxDefaultButton\]::Button2') 'GUI confirmation defaults to No'
Write-Host "TOTAL PASS: $script:Passed"
