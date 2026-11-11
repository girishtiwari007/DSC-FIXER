# Captures rendered console lines only; no real console resize, GUI or repairs.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot;$script:LayoutPass=0
function Assert-Layout($ok,$text){if(-not $ok){throw "FAIL: $text"};$script:LayoutPass++;Microsoft.PowerShell.Utility\Write-Host "PASS: $text"}
foreach($file in 'install.ps1','troubleshooter.ps1'){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $file),[ref]$t,[ref]$e)
 if($e.Count){throw "$file syntax failed"}
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-DscMenu'},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
 $script:DscSessionDirectory='C:\Users\A very long username\AppData\Local\DSC-Signer-Fixer\sessions\2026-11-11_13-00-00_very-long-session-identifier'
 $script:DscLauncherDirectory=$script:DscSessionDirectory
 function Write-Host {param($Object,$ForegroundColor)$script:Lines.Add([string]$Object)}
 function Clear-Host {}
 foreach($size in @(@(120,30),@(80,25),@(60,25),@(40,25),@(80,20),@(60,18),@(40,18))){
  $script:Lines=New-Object 'Collections.Generic.List[string]'
  Show-DscMenu -ViewportWidth $size[0] -ViewportHeight $size[1]
  Assert-Layout (@($script:Lines|Where-Object {$_.Length -ge $size[0]}).Count -eq 0) "$file fits width $($size[0]) without wrapping"
  Assert-Layout (($script:Lines.Count+2) -le $size[1]) "$file leaves space for both prompts at $($size[0])x$($size[1])"
  foreach($number in 1..7){Assert-Layout (@($script:Lines|Where-Object {$_ -match ('Option '+$number+'\. ')}).Count -eq 1) "$file shows Option $number once at $($size[0])x$($size[1])"}
  Assert-Layout (@($script:Lines|Where-Object {$_ -match 'Girish Tiwari'}).Count -eq 1) "$file retains developer credit"
 }
 Remove-Item Function:\Write-Host,Function:\Clear-Host
}
Microsoft.PowerShell.Utility\Write-Host "MENU LAYOUT TOTAL PASS: $script:LayoutPass"
