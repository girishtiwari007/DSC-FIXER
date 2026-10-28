# Isolated temporary hosts fixtures; never reads or writes the system hosts file.
$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('DSS-Hosts-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$repo=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
foreach($name in 'Get-HostsPath','Resolve-Signer','Test-Hosts','Repair-Hosts'){
 $n=$ast.Find({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $name}.GetNewClosure(),$true)
 . ([scriptblock]::Create($n.Extent.Text))
}
$TestMode=$true;$TestRoot=$root;$RunDir=$root;$Cfg=@{SignerHost='eoffsigner.eoffice.gov.in'};$script:Pass=0
function Assert($ok,$text){if(-not $ok){throw "FAIL: $text"};$script:Pass++;Write-Host "PASS: $text"}
function Add-Action{param($r,$text)}
function Write-DscError{param($r,$text)}
$fixtures=@(
 @{Name='concatenated';Text="0.0.0.1`tmssplus.mcafee.com127.0.0.1 eoffsigner.eoffice.gov.in";Before=$false;Keep='0.0.0.1' + "`t" + 'mssplus.mcafee.com'},
 @{Name='single no final newline';Text='127.0.0.1 eoffsigner.eoffice.gov.in';Before=$true;Keep=''},
 @{Name='wrong address and alias';Text='10.1.1.1 eoffsigner.eoffice.gov.in other.example # keep comment';Before=$false;Keep='10.1.1.1 other.example # keep comment'},
 @{Name='duplicate correct entries';Text="127.0.0.1 eoffsigner.eoffice.gov.in`n127.0.0.1 eoffsigner.eoffice.gov.in";Before=$true;Keep=''},
 @{Name='multiple aliases';Text='127.0.0.1 localhost eoffsigner.eoffice.gov.in another.example';Before=$true;Keep='127.0.0.1 localhost another.example'},
 @{Name='comment only';Text="# 10.0.0.2 eoffsigner.eoffice.gov.in`n# preserve this";Before=$false;Keep='# 10.0.0.2 eoffsigner.eoffice.gov.in'},
 @{Name='conflicting duplicate';Text="127.0.0.1 eoffsigner.eoffice.gov.in`n0.0.0.0 eoffsigner.eoffice.gov.in";Before=$false;Keep=''}
)
foreach($fixture in $fixtures){
 $path=Get-HostsPath;[IO.File]::WriteAllText($path,$fixture.Text)
 Assert ((Test-Hosts).Pass -eq $fixture.Before) ($fixture.Name+': diagnosis')
 $originalHash=(Get-FileHash $path).Hash
 Repair-Hosts ([pscustomobject]@{Advice=''})
 $after=[IO.File]::ReadAllText($path)
 Assert ((Test-Hosts).Pass) ($fixture.Name+': valid loopback resolution after repair')
 Assert (([regex]::Matches($after,'(?m)^127\.0\.0\.1 eoffsigner\.eoffice\.gov\.in\r?$')).Count -eq 1) ($fixture.Name+': exactly one separate canonical entry')
 if($fixture.Keep){Assert ($after.Contains($fixture.Keep)) ($fixture.Name+': unrelated mapping/comment preserved')}
 Assert (@(Get-ChildItem $root -Filter 'hosts.backup-*' | Where-Object {(Get-FileHash $_.FullName).Hash -eq $originalHash}).Count -ge 1) ($fixture.Name+': original backup preserved')
 Repair-Hosts ([pscustomobject]@{Advice=''})
 Assert ([IO.File]::ReadAllText($path) -eq $after) ($fixture.Name+': repair is idempotent')
}
# Resolver conflicts must fail even if the first result is correct.
function Resolve-Signer{@('127.0.0.1','10.0.0.4')}
Assert (-not (Test-Hosts).Pass) 'mixed resolver addresses fail'
Write-Host "HOSTS TOTAL PASS: $script:Pass"
