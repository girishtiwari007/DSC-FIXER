# Tests construct the actual dashboard without showing a window or changing the system.
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
$script:ReviewPass=0
function Assert-Review($Condition,[string]$Text){if(-not $Condition){throw "FAIL: $Text"};$script:ReviewPass++;Write-Host "PASS: $Text"}
function Read-ReviewFunction($Ast,[string]$Name){$n=$Ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $Name},$true);if(-not $n){throw "Missing $Name"};$n.Extent.Text}
foreach($file in (Get-ChildItem $repositoryRoot -File | Where-Object Extension -in '.ps1','.bat')){
 $source=[IO.File]::ReadAllText($file.FullName);$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
 if(-not $ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Request-ConsoleReview'},$true)){continue}
 & {
  param($ast,$source,$label)
  foreach($name in 'Get-DscFindingsSummary','Get-DscOverallState','Request-ConsoleReview','Prepare-DscInstaller','Invoke-Fixes','New-Result','Set-FromTest','Get-Label','New-UiFont','Get-SysColor','Get-Failed','Get-Fixable'){
   . ([scriptblock]::Create((Read-ReviewFunction $ast $name)))
  }
  function Say{param($text,$color)}
  function Add-Detail{param($r,$text)}
  function Write-DscError{param($record,$operation)throw "Unexpected error: $operation : $record"}
  $CheckOnly=$false;$script:DiagnosticsOnly=$true;$script:ReviewApproved=$false;$script:Reads=0
  $Results=@{'3'=@{Status='FAIL'}}
  function Find-DssPackageSource{$script:Reads++;throw 'Should not inspect or download a package before review.'}
  Assert-Review (-not (Prepare-DscInstaller) -and $script:Reads -eq 0) "$label initial diagnostics cannot prepare/download an installer"
  $blocked=$false;try{Invoke-Fixes @(3)}catch{$blocked=$true}
  Assert-Review $blocked "$label shared repair engine refuses an unreviewed repair"
  $script:Answers=New-Object 'Collections.Generic.Queue[string]'
  function Ask{param($text,$valid,$default)if($script:Answers.Count){return $script:Answers.Dequeue()};return $default}
  $script:Prepared=0;$script:InstallerDialogs=0
  function Prepare-DscInstaller{$script:Prepared++;return $false}
  function Invoke-InstallerCheckConsole{$script:InstallerDialogs++}
  function Show-Fixable{param($items)}
  $proposals=@(@{No=5;DisplayNo=3;Title='PATH repair'})
  $selection=@(Request-ConsoleReview $proposals)
  Assert-Review ($selection.Count -eq 0 -and $script:Prepared -eq 0 -and $script:InstallerDialogs -eq 0) "$label default console choice finishes without review or preparation"
  $script:Answers.Enqueue('R');$script:Answers.Enqueue('N')
  $selection=@(Request-ConsoleReview $proposals)
  Assert-Review ($selection.Count -eq 0 -and $script:Prepared -eq 1 -and $script:InstallerDialogs -eq 1 -and $script:DiagnosticsOnly) "$label console review can prepare an installer but cancelling selects no repair"
  $script:Answers.Enqueue('R');$script:Answers.Enqueue('A')
  $selection=@(Request-ConsoleReview $proposals)
  Assert-Review ($selection.Count -eq 1 -and $selection[0] -eq 5 -and -not $script:ReviewApproved) "$label explicit console apply returns only the reviewed stable IDs"

  $Cfg=@{DssVersion='4.1.8';Port=55101;EditionName='Test edition';IsLiveUrl='https://eoffsigner.eoffice.gov.in:55101/check/isLive';LnaAllowedOrigins=@('[*.]eoffice.gov.in')}
  $Results=[ordered]@{};$Defs=@();$ByNo=@{}
  $assignment=$ast.Find({param($x)$x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$Defs'},$true)
  $Defs=& ([scriptblock]::Create('return '+$assignment.Right.Extent.Text))
  $index=0
  foreach($definition in $Defs){
   $index++;$definition.DisplayNo=$index;$definition.R=New-Result $definition.No $definition.Title;$definition.R|Add-Member DisplayNo $index
   $ByNo[$definition.No]=$definition;$definition.Tested=$true;$definition.Last=@{Pass=$true}
   Set-FromTest $definition.R @{Pass=$true;Value=('fixture-'+$definition.No)}
  }
  Set-FromTest $Results['4'] @{Pass=$true;Warn=$true;Fixable=$false;Value='success. DSC Signer Service version : 4.1.8 - accepted expiry'}
  $ByNo[4].Last=@{Pass=$true;ExpiredAccepted=$true}
  Set-FromTest $Results['5'] @{Pass=$false;Info=@('PATH repair proposal fixture')}
  $ByNo[5].Last=@{Pass=$false}
  Set-FromTest $Results['8'] @{Pass=$true;Warn=$true;Fixable=$false;Value='browser not verified'}
  $ByNo[8].Last=@{Pass=$true;BrowserVerified=$false;Inconclusive=$true}
  $health=Get-DscOverallState;$others=Get-DscFindingsSummary
  Assert-Review ($health.Working -and $health.Title -notmatch 'NOT WORKING') "$label service health is independent of supplemental failure"
  Assert-Review ($others.Failures -eq 1 -and $others.Warnings -eq 1 -and $others.Unverified -eq 1) "$label separate other-check counts exclude the accepted service expiry"
  $script:JavaUpdateOffer=@{Available=$false};$IsAdmin=$false;$env:DSSF_GUISTUB=$null;$script:Handoff=$null
  $script:GuiDiagnostics=0;$script:GuiReview=0;$script:GuiRepairs=0
  function Invoke-StartupSequence{param([switch]$OpenBrowser,[switch]$FullCheck)$script:GuiDiagnostics++;return $true}
  function Save-Results{'fixture-report.html'}
  function Invoke-Fixes{param($nos)$script:GuiRepairs++}
  $gui=Read-ReviewFunction $ast 'Start-Gui'
  $review=Read-ReviewFunction $ast 'Show-FixChoice'
  $gui=$gui.Replace($review,'function Show-FixChoice { $script:GuiReview++ }')
  $localDialog=Read-ReviewFunction $ast 'Show-PackageDialog'
  $gui=$gui.Replace($localDialog,"function Show-PackageDialog { `$script:LocalMappingDialogs++; return 'exit' }")
  $gui=$gui.Replace("[void][Windows.Forms.MessageBox]::Show('Download was not approved or no valid package was obtained. No installation was changed. See the log or retry Get DSS installer.', 'DSS installer')", '$script:DeclinedNotices++')
  $gui=$gui.Replace('[void]$f.ShowDialog()',@'
    foreach($definition in $Defs){& $script:UiRow $definition}
    Assert-Review ($G.List.CheckedItems.Count -eq 0) 'no repair checkbox is preselected after diagnosis'
    $onShown=$f.GetType().GetMethod('OnShown',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$onShown.Invoke($f,@([EventArgs]::Empty))
    Assert-Review ($script:GuiDiagnostics -eq 1 -and $script:GuiReview -eq 1 -and $script:GuiRepairs -eq 0) 'actual GUI startup completes diagnostics then opens review without repairs'
    Assert-Review ($f.Text.Contains('Test edition') -and $f.Text.Contains('Build 2026.10.27.3')) 'actual window title identifies edition and exact build'
    Assert-Review ($G.Live.Text.StartsWith('Signer service: WORKING') -and $G.Findings.Text.StartsWith('Other checks: 1 need attention')) 'actual dashboard shows service and other checks separately'
    Assert-Review ($G.BFix.Text -eq 'Review / Pending fixes ...') 'main action explicitly reviews before applying'
    $onClick=$G.BTest.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$onClick.Invoke($G.BTest,@([EventArgs]::Empty))
    Assert-Review ($script:GuiDiagnostics -eq 2 -and $script:GuiReview -eq 1 -and $script:GuiRepairs -eq 0) 'later full checks do not repeat the initial review'
    $script:Handoff=@{fix=@(5)}
    [void]$onShown.Invoke($f,@([EventArgs]::Empty))
    Assert-Review ($script:GuiRepairs -eq 0 -and $script:GuiReview -eq 1) 'actual elevated-handoff startup does not resume repairs automatically'
    $reviewClick=$G.BFix.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$reviewClick.Invoke($G.BFix,@([EventArgs]::Empty))
    Assert-Review ($script:GuiReview -eq 2 -and $script:GuiRepairs -eq 0) 'explicit review click reaches review without applying anything'
    # Construct the real review modal, replacing only its blocking display call.
    $actualReview=$review.Replace('[void]$d.ShowDialog($script:G.Form)',"Assert-Review (`$d.AcceptButton -eq `$bn -and `$d.CancelButton -eq `$bn) 'Enter and Escape default to no repair'; Assert-Review (`$ba.Text.StartsWith('Apply listed')) 'Apply is an explicit separate review action'")
    . ([scriptblock]::Create($actualReview))
    Show-FixChoice
    Assert-Review ($script:GuiRepairs -eq 0 -and -not $script:ReviewApproved) 'closing the actual review modal applies no repair'
    $Cfg.AllowDssDownload=$true;$Cfg.PackageUrl='https://example.invalid/fixture.zip'
    $script:PackageRequests=0;$script:LocalMappingDialogs=0;$script:DeclinedNotices=0;$script:PackageApproved=$true
    function Start-DssInstallRequest {$script:PackageRequests++;$script:DssInstallOutcome=$(if($script:PackageApproved){'Installed'}else{'Declined'});return $script:PackageApproved}
    $getInstallerClick=$G.BLocate.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$getInstallerClick.Invoke($G.BLocate,@([EventArgs]::Empty))
    Assert-Review ($script:PackageRequests -eq 1 -and $script:LocalMappingDialogs -eq 0) 'actual download/install button routes approved requests and continues without a mapping dialog'
    $script:PackageApproved=$false
    [void]$getInstallerClick.Invoke($G.BLocate,@([EventArgs]::Empty))
    Assert-Review ($script:PackageRequests -eq 2 -and $script:LocalMappingDialogs -eq 0 -and $script:DeclinedNotices -eq 0) 'actual declined GUI request does not fall back to manual mapping'
    $G.JavaTimer.Dispose();$G.Flash.Dispose();$f.Dispose()
'@)
  . ([scriptblock]::Create($gui))
  Start-Gui
  $startup=Read-ReviewFunction $ast 'Invoke-StartupSequence'
  Assert-Review ($startup.Contains('$script:DiagnosticsOnly=$true') -and $startup.Contains('$script:ReviewApproved=$false')) "$label every diagnostic rerun clears prior apply permission"
  $apply=Read-ReviewFunction $ast 'Invoke-GuiFix'
  Assert-Review ($apply.Contains('Invoke-Fixes $nos')) "$label selected repairs retain the shared guarded engine"
 } $ast $source $file.Name
}
Write-Host "REVIEW TOTAL PASS: $script:ReviewPass; PowerShell $($PSVersionTable.PSVersion)"
