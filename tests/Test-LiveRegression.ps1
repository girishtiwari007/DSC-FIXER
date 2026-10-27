$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
$fixtureRoot=Join-Path $env:TEMP ('DSC-LiveRegression-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$script:LivePass=0
function Assert-Live($Condition,[string]$Text){if(-not $Condition){throw "FAIL: $Text"};$script:LivePass++;Write-Host "PASS: $Text"}
function Read-LiveFunction($Ast,[string]$Name){$n=$Ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $Name},$true);if(-not $n){throw "Missing $Name"};$n.Extent.Text}
foreach($file in (Get-ChildItem $repositoryRoot -File | Where-Object Extension -in '.ps1','.bat')){
 $source=[IO.File]::ReadAllText($file.FullName);$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
 $has=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Get-DscOverallState'},$true)
 if(-not $has){continue}
 & {
  param($ast,$source,$label,$fixtureRoot)
  foreach($name in 'Get-DscFindingsSummary','Request-ConsoleReview','Get-DscOverallState','Get-Failed','Get-Fixable','Invoke-JavaVersion','Wait-Proc','Test-ChromiumBrowser','Test-DscLiveResponse','Set-FromTest','New-Result','Get-Label','New-UiFont','Get-SysColor'){
   . ([scriptblock]::Create((Read-LiveFunction $ast $name)))
  }
  function Update-Ui {}
  function Log {param($text)}
  function Write-DscError {param($record,$operation)throw "Unexpected: $operation : $record"}
  $Cfg=@{DssVersion='4.1.8';Port=55101;IsLiveUrl='https://eoffsigner.eoffice.gov.in:55101/check/isLive';LnaAllowedOrigins=@('[*.]eoffice.gov.in')}
  $Results=[ordered]@{};$ByNo=@{};$Defs=@()
  $assignment=$ast.Find({param($x)$x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$Defs'},$true)
  $Defs=& ([scriptblock]::Create('return '+$assignment.Right.Extent.Text))
  $sequence=0
  foreach($d in $Defs){$sequence++;$d.DisplayNo=$sequence;$d.R=New-Result $d.No $d.Title;$d.R|Add-Member DisplayNo $sequence;$ByNo[$d.No]=$d;$d.Tested=$true;$d.Last=@{Pass=$true};Set-FromTest $d.R @{Pass=$true;Value=('value-'+$d.No)}}
  $ByNo[4].Last=@{Pass=$true;ExpiredAccepted=$true};Set-FromTest $Results['4'] @{Pass=$true;Warn=$true;Fixable=$false;Value='success. DSC Signer Service version : 4.1.8 - accepted expiry'}
  Set-FromTest $Results['6'] @{Pass=$false;Info=@('Actual hosts issue fixture')}
  Assert-Live ((Get-DscOverallState).Working) "$label isLive success remains WORKING despite another check failing"
  Assert-Live ((Get-DscOverallState).Title -notmatch 'NOT WORKING') "$label accepted expiry is never a NOT WORKING verdict"
  $ByNo[4].Last=@{Pass=$false};$Results['4'].Status='FAIL'
  Assert-Live (-not (Get-DscOverallState).Working -and (Get-DscOverallState).Verified) "$label real isLive failure remains a failure"
  $ByNo[4].Last=@{DiagnosticError=$true};$Results['4'].Status='WARN'
  Assert-Live (-not (Get-DscOverallState).Verified) "$label unavailable isLive is not misrepresented as a confirmed failure"
  $ByNo[4].Last=@{Pass=$true;ExpiredAccepted=$true};$Results['4'].Status='WARN'
  $r=New-Result 99 'probe'
  Set-FromTest $r @{Pass=$false;DiagnosticError=$true}
  Assert-Live ($r.Status -eq 'WARN' -and -not $r.Fixable) "$label a diagnostic exception does not invent a repairable defect"
  function Find-Browser {param($name)@{Name=$name;Exe='fixture';Version='fixture'}}
  $script:BrowserProbe=@{Html='';Err='';Inconclusive=$true}
  function Invoke-HeadlessCheck {param($b)$script:BrowserProbe}
  function Get-LnaValues {param($name)@('[*.]eoffice.gov.in')}
  $browser=Test-ChromiumBrowser 'Chrome'
  Assert-Live ($browser.Pass -and $browser.Warn -and -not $browser.Fixable -and -not $browser.BrowserVerified) "$label empty browser output is unverified, never an automatic repair"
  $script:BrowserProbe=@{Html='';Err='ERR_CERT_DATE_INVALID';Inconclusive=$false}
  Assert-Live ((Test-ChromiumBrowser 'Edge').Warn) "$label browser expiry follows the accepted isLive expiry"
  $script:BrowserProbe=@{Html='';Err='ERR_CERT_AUTHORITY_INVALID';Inconclusive=$false}
  Assert-Live (-not (Test-ChromiumBrowser 'Edge').Pass) "$label genuine browser trust failures remain visible"
  $script:BrowserProbe=@{Html='success. DSC Signer Service version : 4.1.8';Err='';Inconclusive=$false}
  Assert-Live ((Test-ChromiumBrowser 'Chrome').BrowserVerified) "$label real page content is verified separately"
  # A real native child emits the successful Java response on stderr, as Java does.
  $exe=Join-Path $fixtureRoot ('java-'+[guid]::NewGuid().ToString('N')+'.exe')
  $class='JavaFixture'+[guid]::NewGuid().ToString('N')
  $code='public class '+$class+' { public static void Main(string[] args) { System.Console.Error.WriteLine("java version \"1.8.0_202\""); } }'
  Add-Type -TypeDefinition $code -OutputAssembly $exe -OutputType ConsoleApplication
  $native=Invoke-JavaVersion $exe
  Assert-Live ($native.Code -eq 0 -and $native.Text -match '1.8.0_202') "$label successful stderr output is native text, not an exception"
  # Construct the actual dashboard and run its actual callbacks against reordered definitions.
  $script:JavaUpdateOffer=@{Available=$false};$IsAdmin=$false;$env:DSSF_GUISTUB=$null
  $gui=Read-LiveFunction $ast 'Start-Gui'
  $gui=$gui.Replace('[void]$f.ShowDialog()',@'
    foreach($definition in $Defs){ & $script:UiRow $definition }
    Assert-Live ($G.List.Items.Count -eq 10) 'dashboard has all ten ordered rows'
    $index=0
    foreach($definition in $Defs){
        $row=$G.RowsById[[int]$definition.No]
        Assert-Live ($row.Tag -eq $definition.No -and $row.SubItems[3].Text -eq $definition.R.Value -and $row.SubItems[1].Text -eq $definition.Title) ('correct title/status/value mapping for internal check '+$definition.No)
        $index++;Assert-Live ($G.List.Items[$index-1].Text -eq [string]$index) ('visible check number '+$index)
    }
    Update-Summary
    Assert-Live ($G.Live.Text.StartsWith('Signer service: WORKING')) 'actual GUI banner respects isLive success despite other failures'
    $G.JavaTimer.Dispose();$G.Flash.Dispose();$f.Dispose()
'@)
  . ([scriptblock]::Create($gui))
  Start-Gui
 } $ast $source $file.Name $fixtureRoot
}
Write-Host "LIVE TOTAL PASS: $script:LivePass; PowerShell $($PSVersionTable.PSVersion)"
