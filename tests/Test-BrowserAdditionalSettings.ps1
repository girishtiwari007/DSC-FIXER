# Fixtures only. No actual browser, clipboard, startup setting or bookmark database changes.
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $root 'install.ps1'));$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e);if($e.Count){throw 'Source parse failed'}
$script:Pass=0
function Assert-Browser($ok,$name){if(-not $ok){throw "FAIL: $name"};$script:Pass++;Write-Host "PASS: $name"}
function Browser-Function($name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"};$n.Extent.Text}
foreach($name in 'Get-DscBrowserSetupDefinition','New-DscBookmarkImportFile','Get-DscBrowserSetupInstructions','Open-DscBrowserAdditionalSettings'){
 . ([scriptblock]::Create((Browser-Function $name)))
}
$RunDir=Join-Path $env:TEMP ('DscBrowserSetup-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($RunDir)
$TestMode=$false;$script:Opened=@();$script:Events=@();$script:Prompts=@();$script:Decline=$false
function Start-Process{param($FilePath,$ArgumentList,$ErrorAction)$script:Opened+=@{Exe=$FilePath;Url=$ArgumentList}}
function Find-Browser($Name){[pscustomobject]@{Exe=($Name+'.exe')}}
function Confirm-DscBrowserSetup($Message,$Title){$script:Prompts+=$Title;return (-not $script:Decline)}
function Write-DscEvent{param($level,$operation,$data)$script:Events+=@{Operation=$operation;Data=$data}}
function Write-DscError{param($record,$operation)throw "Unexpected error: $operation $record"}
Assert-Browser ((Get-DscBrowserSetupDefinition Chrome).Startup -eq 'chrome://settings/onStartup') 'Chrome uses supported startup settings page'
Assert-Browser ((Get-DscBrowserSetupDefinition Edge).Startup -eq 'edge://settings/startHomeNTP') 'Edge uses supported startup/home settings page'
Assert-Browser ((Get-DscBrowserSetupDefinition Firefox).Startup -eq 'about:preferences#home') 'Firefox uses Home settings page'
$blocked=$false;try{Get-DscBrowserSetupDefinition Other}catch{$blocked=$true};Assert-Browser $blocked 'unknown browser rejected'
$blocked=$false;try{New-DscBookmarkImportFile}catch{$blocked=$true};Assert-Browser ($blocked -and -not (Test-Path (Join-Path $RunDir 'DSC-isLive-bookmark.html'))) 'no import file without approval'
$blocked=$false;try{Open-DscBrowserAdditionalSettings @('Chrome') -Bookmark}catch{$blocked=$true};Assert-Browser ($blocked -and $script:Opened.Count -eq 0) 'no browser launch without approval'
$blocked=$false;try{Open-DscBrowserAdditionalSettings @('Chrome') -Confirmed}catch{$blocked=$true};Assert-Browser $blocked 'at least one action required'
$blocked=$false;try{Open-DscBrowserAdditionalSettings @('Chrome','Other') -Bookmark -Confirmed}catch{$blocked=$true};Assert-Browser ($blocked -and $script:Opened.Count -eq 0) 'all browser names validated before creating or opening anything'
$file=Open-DscBrowserAdditionalSettings @('Chrome','Edge','Firefox') -Bookmark -Startup -Confirmed
$html=[IO.File]::ReadAllText($file)
Assert-Browser ($html -match '>DSC islive Check</A>' -and @([regex]::Matches($html,'HREF=')).Count -eq 1) 'import file contains exactly one correctly named bookmark'
Assert-Browser ($html -match 'https://eoffsigner.eoffice.gov.in:55101/check/isLive' -and $html -notmatch '<script') 'bookmark import uses exact endpoint and contains no script'
Assert-Browser ($script:Opened.Count -eq 6 -and $script:Prompts.Count -eq 3) 'each selected browser asks once and opens only selected bookmark/startup pages'
Assert-Browser (@($script:Events|Where-Object{$_.Operation -match 'pending user action'}).Count -eq 3) 'opened settings recorded as pending rather than saved'
$before=$script:Opened.Count;$script:Decline=$true
[void](Open-DscBrowserAdditionalSettings @('Chrome') -Startup -Confirmed)
Assert-Browser ($script:Opened.Count -eq $before) 'per-browser Cancel opens nothing'
$script:Decline=$false
[void](Open-DscBrowserAdditionalSettings @('Edge','Edge') -Startup -Confirmed)
Assert-Browser ($script:Opened.Count -eq ($before+1)) 'duplicate browser choices do not duplicate startup windows'
$before=$script:Opened.Count
function Find-Browser($Name){$null}
[void](Open-DscBrowserAdditionalSettings @('Firefox') -Bookmark -Confirmed)
Assert-Browser ($script:Opened.Count -eq $before -and $script:Events[-1].Operation -match 'not installed') 'missing browser skipped without claiming success'
$guide=Get-DscBrowserSetupInstructions Firefox -Startup
Assert-Browser ($guide -match 'Keep all existing URLs' -and $guide -match '\|' -and $guide -match 'Restore previous session') 'Firefox guide preserves existing homepages and explains session mode'
Assert-Browser ($guide -match 'Certificate expiry warnings are not removed') 'bookmark/startup setup never claims to fix TLS errors'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$gui=Browser-Function 'Show-DscBrowserAdditionalSettings'
$gui=$gui.Replace('[void]$d.ShowDialog($Owner)',@'
Assert-Browser (@($boxes.Values|Where-Object Checked).Count -eq 0 -and -not $bookmark.Checked -and -not $startup.Checked) 'actual GUI defaults all browser/action choices to unchecked'
Assert-Browser ($d.AcceptButton -eq $cancel -and $d.CancelButton -eq $cancel) 'actual GUI defaults Enter/Escape to Cancel'
Assert-Browser ($continue.Text -eq 'Continue' -and $notes.ReadOnly -and $url.ReadOnly) 'actual GUI uses Continue with readable protected instructions and URL'
'@)
. ([scriptblock]::Create($gui));$owner=New-Object Windows.Forms.Form
try{Show-DscBrowserAdditionalSettings $owner}finally{$owner.Dispose()}
Assert-Browser ($source.Contains('DSC islive Check - Bookmark / Startup setup') -and -not $source.Contains('$o.BrowserSetup')) 'one optional bookmark/startup entry in the current full GUI only'
Write-Host "BROWSER SETTINGS TOTAL PASS: $script:Pass"
