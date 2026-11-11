# Simulated host only: does not alter the actual terminal theme or window.
$ErrorActionPreference='Stop';$repo=Split-Path -Parent $PSScriptRoot;$script:ThemePass=0
function Assert-Theme($ok,$message){if(-not $ok){throw "FAIL: $message"};$script:ThemePass++;Microsoft.PowerShell.Utility\Write-Host "PASS: $message"}
foreach($file in 'install.ps1','troubleshooter.ps1'){
 $text=[IO.File]::ReadAllText((Join-Path $repo $file));$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e)
 if($e.Count){throw 'Source syntax failed'}
 $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-DscMenu'},$true)
 $menu=$node.Extent.Text.Replace("`$interactive=`$Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected",'$interactive=$true').Replace('$Host','$script:FixtureHost')
 . ([scriptblock]::Create($menu))
 $script:FixtureHost=[pscustomobject]@{UI=[pscustomobject]@{SupportsVirtualTerminal=$true;RawUI=[pscustomobject]@{BackgroundColor='Gray';ForegroundColor='Black';WindowTitle='Original title';WindowSize=[pscustomobject]@{Width=80;Height=25}}}}
 $script:DscLauncherTheme=$null;$script:DscMenuTheme=$null;$script:ThemeLines=@();$script:Clears=0
 function Write-Host {param($Object,$ForegroundColor)$script:ThemeLines+= [string]$Object}
 function Clear-Host {$script:Clears++}
 function Write-DscLauncherEvent {param($operation,$data)}
 Show-DscMenu -ViewportWidth 80 -ViewportHeight 25
 Assert-Theme ($script:FixtureHost.UI.RawUI.BackgroundColor -eq 'DarkBlue' -and $script:FixtureHost.UI.RawUI.ForegroundColor -eq 'White') "$file applies the PowerShell blue-and-white palette"
 Assert-Theme ($script:FixtureHost.UI.RawUI.WindowTitle -match 'Windows PowerShell' -and $script:Clears -eq 1) "$file sets title and clears once"
 Assert-Theme (@($script:ThemeLines|Where-Object {$_ -match '\x1b\[1m.*Digital Signing'}).Count -eq 1) "$file renders a bold heading on supported terminals"
 Assert-Theme ($script:FixtureHost.UI.RawUI.WindowSize.Width -eq 80 -and $script:FixtureHost.UI.RawUI.WindowSize.Height -eq 25) "$file leaves console dimensions unchanged"
 Show-DscMenu -ViewportWidth 80 -ViewportHeight 25
 $theme=if($file -eq 'install.ps1'){$script:DscLauncherTheme}else{$script:DscMenuTheme}
 Assert-Theme ($theme.Background -eq 'Gray' -and $theme.Title -eq 'Original title') "$file preserves the original theme across menu refresh"
 $variable=if($file -eq 'install.ps1'){'$script:DscLauncherTheme'}else{'$script:DscMenuTheme'}
 $restore=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.Contains($variable+'.Background') -and $n.Extent.Text.Contains($variable+'=$null')},$true)
 Assert-Theme ([bool]$restore) "$file has an exit restoration guard"
 & ([scriptblock]::Create($restore.Extent.Text.Replace('$Host','$script:FixtureHost')))
 Assert-Theme ($script:FixtureHost.UI.RawUI.BackgroundColor -eq 'Gray' -and $script:FixtureHost.UI.RawUI.ForegroundColor -eq 'Black' -and $script:FixtureHost.UI.RawUI.WindowTitle -eq 'Original title') "$file restores the original palette and title"
 Remove-Item Function:\Write-Host,Function:\Clear-Host,Function:\Write-DscLauncherEvent
}
Microsoft.PowerShell.Utility\Write-Host "CONSOLE THEME TOTAL PASS: $script:ThemePass"
