# Fixtures only: no real network, process changes, installers or repairs.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source syntax failed'}
$function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-DssInstallRequest'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$script:Pass=0
function Assert($condition,$message){if(-not $condition){throw "FAIL: $message"};$script:Pass++;Write-Host "PASS: $message"}
function Write-DscEvent{param($a,$b,$c)}
function Write-DscError{param($a,$b)}
function Add-Detail{param($a,$b)}
function Say{param($a,$b)}
$script:Asks=0;$script:Repairs=0;$script:Tests=0;$script:Approval=$false;$script:RepairError=$false
function Read-DssDownloadApproval{param($message)$script:Asks++;return $script:Approval}
function Test-DssInstall{$script:Tests++;@{Pass=($script:Repairs -gt 0);Old=@();Exe=''}}
function Repair-DssInstall{param($r,$t)
 if(-not $script:ReviewApproved -or $script:DiagnosticsOnly){throw 'Missing explicit review permission'}
 if($script:DssDownloadConsent -ne 'Granted'){throw 'Missing download consent'}
 $script:Repairs++
 if($script:RepairError){$script:DssPackageFailure='HTTP 403 from fixture source';throw 'No valid package'}
}
$Cfg=@{DssVersion='4.1.8';PackageUrl='https://example.invalid/dss.zip';PackageSha256='';AllowDssDownload=$true}
$Results=@{'3'=@{Status='FAIL'}};$ByNo=@{3=@{R=$Results['3'];Fixed=$false}}
$script:DiagnosticsOnly=$true;$script:ReviewApproved=$false
$CheckOnly=$true;$IsAdmin=$true
Assert (-not (Start-DssInstallRequest) -and $script:Asks -eq 0 -and $script:Repairs -eq 0) 'check-only never prompts or installs'
$CheckOnly=$false;$IsAdmin=$false
Assert (-not (Start-DssInstallRequest) -and $script:Asks -eq 0 -and $script:Repairs -eq 0 -and $script:DssPackageFailure -match 'Administrator') 'non-admin receives actionable guidance before any download'
$IsAdmin=$true
Assert (-not (Start-DssInstallRequest) -and $script:DssInstallOutcome -eq 'Declined' -and $script:Repairs -eq 0 -and $script:Tests -eq 0) 'declining combined action does not inspect or change installation'
$script:Approval=$true
Assert ((Start-DssInstallRequest) -and $script:Repairs -eq 1 -and $script:Tests -eq 2 -and $ByNo[3].Fixed) 'one approved action runs shared installation then validates actual state'
Assert ($script:Asks -eq 2) 'approved combined action asks once, with no second download prompt'
Assert ($script:DiagnosticsOnly -and -not $script:ReviewApproved) 'apply permission is restored after success'
$script:Repairs=0;$script:RepairError=$true
Assert (-not (Start-DssInstallRequest) -and $script:DssPackageFailure -match 'HTTP 403' -and $script:DssInstallOutcome -eq 'Failed') 'failure preserves specific download reason and never reports success'
Assert ($script:DiagnosticsOnly -and -not $script:ReviewApproved) 'apply permission is restored after failure'
Write-Host "INSTALL CONTINUE TOTAL PASS: $script:Pass"
