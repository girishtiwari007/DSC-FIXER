$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$engine=Join-Path $repo 'troubleshooter.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($engine,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Troubleshooting engine syntax is invalid.'}
$menu=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-DscMenu'},$true).Extent.Text
if(-not $menu){throw 'Menu function missing from engine.'}
$menu=$menu.Replace('$script:DscSessionDirectory','$script:DscLauncherDirectory')
$menu=$menu.Replace('Native PowerShell | Build','Menu first | Build')
$template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'launcher.template.ps1'))
$launcher=$template.Replace('@ENGINE_SHA256@',(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash).Replace('# @MENU@',$menu)
[void][Management.Automation.Language.Parser]::ParseInput($launcher,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Generated launcher syntax is invalid.'}
[IO.File]::WriteAllText((Join-Path $repo 'install.ps1'),$launcher,(New-Object Text.UTF8Encoding $true))
Write-Host ('Menu launcher: '+[Text.Encoding]::UTF8.GetByteCount($launcher)+' bytes; engine: '+(Get-Item $engine).Length+' bytes.')
