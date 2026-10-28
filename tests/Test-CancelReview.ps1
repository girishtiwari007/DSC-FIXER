# Simulation-only: no real repairs, installers, firewall or security changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
function Get-Function($name){$n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name}.GetNewClosure(),$true);$n.Extent.Text}
foreach($name in 'Invoke-Fixes','Show-InitialPendingReview'){. ([scriptblock]::Create((Get-Function $name)))}
$script:Pass=0
function Assert($ok,$text){if(-not $ok){throw "FAIL: $text"};$script:Pass++;Write-Host "PASS: $text"}
function Say{param($a,$b)}
function Write-DscEvent{param($a,$b,$c)}
function Write-DscError{param($a,$b)}
function Add-Detail{param($a,$b)}
function Add-Action{param($a,$b)}
function Log{param($a)}
function Update-Ui{}
$script:Reviews=0
function Get-Fixable{@(@{No=5})}
function Show-FixChoice{$script:Reviews++}
$script:InitialReviewShown=$false
Show-InitialPendingReview;Show-InitialPendingReview
Assert ($script:Reviews -eq 1) 'first completed diagnostic opens review exactly once'
$script:InitialReviewShown=$false
function Get-Fixable{@()}
Show-InitialPendingReview
Assert ($script:Reviews -eq 1) 'healthy results do not open an empty review'
$review=Get-Function 'Show-FixChoice'
Assert (-not $review.Contains('Prepare-DscInstaller') -and -not $review.Contains('Start-DssPackageRequest')) 'review does not wait on a download or package mapping'
Assert ($review.Contains("`$bn.Text = 'Cancel fixes'") -and $review.Contains('$d.CancelButton = $bn') -and $review.Contains('$d.AcceptButton = $bn')) 'Cancel fixes is the modal default for Enter and Escape'
$FixOrder=@(5,3);$script:Executed=@();$script:ReviewApproved=$true;$script:CancelRequested=$true;$script:UiStatus=$null
$ByNo=@{}
foreach($n in $FixOrder){$ByNo[$n]=@{No=$n;Title='fixture';Fixed=$false;R=[pscustomobject]@{Status='FAIL';Advice=''};T={@{Pass=$false;Warn=$false}};F={param($r,$t)$script:Executed+='repair'}}}
Invoke-Fixes $FixOrder
Assert ($script:Executed.Count -eq 0 -and -not $ByNo[5].Fixed) 'cancellation before apply performs no repairs'
$script:CancelRequested=$false
$ByNo[5].F={param($r,$t)$script:Executed+='current-finished';$script:CancelRequested=$true}
Invoke-Fixes $FixOrder
Assert (($script:Executed -join ',') -eq 'current-finished' -and -not $ByNo[3].Fixed) 'current operation completes, remaining repair is skipped'
$script:CancelRequested=$false;$script:Executed=@();$ByNo[5].Fixed=$false
$ByNo[5].T={$script:CancelRequested=$true;@{Pass=$false;Warn=$false}}
Invoke-Fixes $FixOrder
Assert ($script:Executed.Count -eq 0 -and -not $ByNo[5].Fixed) 'cancel during precheck prevents applying the repair'
$script:ReviewApproved=$false;$script:CancelRequested=$false;$blocked=$false
try{Invoke-Fixes $FixOrder}catch{$blocked=$true}
Assert $blocked 'automatic review does not authorize automatic repairs'
$service=Get-Function 'Start-DssAdmin'
Assert ($service.Contains('Windows/Java') -and $service.Contains('Update-Ui') -and $service.Contains('Do not approve unrelated Java')) 'service start stays responsive and explains targeted Java Allow prompts'
Assert (-not $service.Contains('New-NetFirewallRule') -and -not $service.Contains('Set-NetFirewallProfile')) 'service guidance does not silently alter firewall rules'
Write-Host "CANCEL REVIEW TOTAL PASS: $script:Pass"
