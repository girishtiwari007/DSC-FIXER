# Actual WinForms construction with fixture status and mocked mutations only.
$ErrorActionPreference='Stop';$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'troubleshooter.ps1'));$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Source parse failed'}
function Read-CrisUiFunction($name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name},$true);if(-not $n){throw "Missing $name"};$n.Extent.Text}
$script:SimplePass=0
function Assert-Simple($ok,$message){if(-not $ok){throw "FAIL: $message"};$script:SimplePass++;Write-Host "PASS: $message"}
. ([scriptblock]::Create((Read-CrisUiFunction 'Get-CrisCatalog')))
function Get-CrisState($id){@{State=$(if($id -eq 'IPAS'){'RUNNING'}else{'STOPPED'});Color=$(if($id -eq 'IPAS'){'ForestGreen'}else{'Firebrick'});Detail='fixture status'}}
function Save-DscSession{param($r)}
function Write-DscError{param($r,$op)throw "Unexpected $op : $r"}
function Get-CrisExistingProducts{@()}
function Invoke-CrisSetupBoth{param([switch]$Confirmed,$ApprovedExistingCodes)if(-not $Confirmed){throw 'No approval'};$script:SetupCalls++}
function Save-CrisDesktopSwitcher{param([switch]$Confirmed)if(-not $Confirmed){throw 'No approval'};$script:DesktopCalls++}
$gui=Read-CrisUiFunction 'Start-CrisGui'
$gui=$gui.Replace((Read-CrisUiFunction 'Confirm-CrisUi'),'function Confirm-CrisUi {param($message,$title)return $script:ContinueApproved}')
$gui=$gui.Replace('[void]$f.ShowDialog()',@'
Assert-Simple ($u.Rows.Count -eq 2) 'two clear signer cards are present'
Assert-Simple (-not $u.Advanced.Checked -and -not $u.Details.Checked -and $root.RowStyles[6].Height -eq 0) 'advanced tools and log start collapsed'
Assert-Simple (-not $u.Busy -and -not $u.Cancel.Enabled -and $f.CancelButton -eq $u.Close) 'opening the window is idle and Escape closes it'
Refresh-CrisUi
Assert-Simple ($u.Rows.IPAS.Text -match 'RUNNING.*2068' -and $u.Rows.IRWCMS.Text -match 'STOPPED.*2039') 'cards show signer status and the correct ports'
Assert-Simple ($u.Rows.IPAS.ForeColor.Name -eq 'ForestGreen' -and $u.Rows.IRWCMS.ForeColor.Name -eq 'Firebrick') 'running and stopped use distinct green and red states'
$u.Details.Checked=$true
Assert-Simple ($root.RowStyles[6].Height -eq 110) 'details can be expanded on request'
$u.Details.Checked=$false
if($RequestedMode -eq 'crisswitch'){
 Assert-Simple ($u.SwitcherOnly -and $f.Text -eq 'CRIS Signer Switcher' -and $actions.ColumnStyles[1].Width -eq 0) 'desktop opens the compact switcher-only view'
 Assert-Simple ($script:SetupCalls -eq 0 -and $script:DesktopCalls -eq 0) 'desktop switcher never installs or creates shortcuts on launch'
}else{
 Assert-Simple (-not $u.SwitcherOnly -and $u.Setup.Text -match 'Install / Repair' -and $u.Refresh.Text -match 'Check / Refresh') 'Option 5 presents check first and one explicit setup action'
 $click=$u.Setup.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
 $script:ContinueApproved=$false;[void]$click.Invoke($u.Setup,@([EventArgs]::Empty))
 Assert-Simple ($script:SetupCalls -eq 0) 'cancelling setup review causes no installation'
 $script:ContinueApproved=$true;[void]$click.Invoke($u.Setup,@([EventArgs]::Empty))
 Assert-Simple ($script:SetupCalls -eq 1) 'approved setup runs the guarded existing installer once'
 $script:ContinueApproved=$false;[void]$click.Invoke($u.Desktop,@([EventArgs]::Empty))
 Assert-Simple ($script:DesktopCalls -eq 0) 'cancelling desktop request creates nothing'
 $script:ContinueApproved=$true;[void]$click.Invoke($u.Desktop,@([EventArgs]::Empty))
 Assert-Simple ($script:DesktopCalls -eq 1) 'desktop switcher can be created separately after approval'
 Invoke-CrisUiWork {$script:CancelRequested=$true;$script:CrisUi.Progress.Value=45}
 Assert-Simple ($u.Progress.Value -eq 45 -and $u.Status.Text -match 'Cancelled') 'cancellation retains partial progress'
}
if($env:CRIS_PREVIEW_DIR){
 [void][IO.Directory]::CreateDirectory($env:CRIS_PREVIEW_DIR)
 $f.StartPosition='Manual';$f.Location=New-Object Drawing.Point(-10000,-10000);$f.Show();[Windows.Forms.Application]::DoEvents()
 @($u.Refresh,$u.Setup)|ForEach-Object { [pscustomobject]@{Text=$_.Text;Bounds=$_.Bounds.ToString();Client=$_.ClientRectangle.ToString();Preferred=$_.PreferredSize.ToString();Foreground=$_.ForeColor.ToString();Visible=$_.Visible;Font=$_.Font.ToString()} }|ConvertTo-Json|Set-Content (Join-Path $env:CRIS_PREVIEW_DIR ($RequestedMode+'-controls.json'))
 $bitmap=New-Object Drawing.Bitmap($f.Width,$f.Height)
 try{$f.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$f.Width,$f.Height)));$bitmap.Save((Join-Path $env:CRIS_PREVIEW_DIR ($RequestedMode+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose();$f.Close()}
}
'@)
. ([scriptblock]::Create($gui))
$IsAdmin=$true;$script:Ui=$null;$script:UiLog=$null;$script:UiStatus=$null;$script:DscSessionDirectory='Fixture session - no actual signer checks';$Results=@{}
foreach($RequestedMode in 'crisgui','crisswitch'){$script:SetupCalls=0;$script:DesktopCalls=0;$script:ContinueApproved=$false;Start-CrisGui}
Assert-Simple ($source.Contains('+ $copy') -or $source.Contains(' -Mode crisswitch')) 'desktop shortcut uses its switcher-only entry mode'
Write-Host "CRIS SIMPLE GUI TOTAL PASS: $script:SimplePass"
