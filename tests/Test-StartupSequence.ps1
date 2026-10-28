# Fixture-only workflow tests: no network, browsers, installers, trust stores or repairs.
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
$fixtureRoot=Join-Path $env:TEMP ('DSC-WorkflowTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$script:WorkflowPass=0
function Assert-Workflow($Condition,[string]$Description) {
    if(-not $Condition){throw "FAIL: $Description"}
    $script:WorkflowPass++;Write-Host "PASS: $Description"
}
function Read-WorkflowFunction($Ast,[string]$Name) {
    $n=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if(-not $n){throw "Missing $Name"};return $n.Extent.Text
}
foreach($file in (Get-ChildItem -LiteralPath $repositoryRoot -File | Where-Object Extension -in '.ps1','.bat')) {
    $source=[IO.File]::ReadAllText($file.FullName);$tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert-Workflow ($errors.Count -eq 0) "$($file.Name) parses"
    $gate=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-StartupSequence'},$true)
    if(-not $gate){continue}
    & {
        param($ast,$source,$label,$directory,$fixtureRoot)
        if(-not ('DssfHttpV3' -as [type])) {
            $begin=$source.IndexOf('using System;');$end=$source.IndexOf("`n'@",$begin)
            Add-Type -TypeDefinition $source.Substring($begin,$end-$begin) -ErrorAction Stop
        }
        $url='https://eoffsigner.eoffice.gov.in:55101/check/isLive'
        $now=[DateTime]::UtcNow
        $chainError=[Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors
        $timeOnly=[Security.Cryptography.X509Certificates.X509ChainStatusFlags[]]@('NotTimeValid')
        $starts=[DateTime[]]@($now.AddYears(-2));$ends=[DateTime[]]@($now.AddDays(-1))
        Assert-Workflow ([DssfHttpV3]::IsExpiryOnly($url,$chainError,$timeOnly,$starts,$ends,$now)) "$label accepts expiry-only signer certificate alert"
        foreach($badUrl in 'https://example.com:55101/check/isLive','https://eoffsigner.eoffice.gov.in:443/check/isLive','https://eoffsigner.eoffice.gov.in:55101/other','http://eoffsigner.eoffice.gov.in:55101/check/isLive','https://eoffsigner.eoffice.gov.in:55101/check/isLive?other=1','https://name@eoffsigner.eoffice.gov.in:55101/check/isLive') {
            Assert-Workflow (-not [DssfHttpV3]::IsExpiryOnly($badUrl,$chainError,$timeOnly,$starts,$ends,$now)) "$label expiry exception rejects another endpoint: $badUrl"
        }
        $unknownRoot=[Security.Cryptography.X509Certificates.X509ChainStatusFlags[]]@('NotTimeValid','UntrustedRoot')
        Assert-Workflow (-not [DssfHttpV3]::IsExpiryOnly($url,$chainError,$unknownRoot,$starts,$ends,$now)) "$label expiry does not hide an unknown root"
        $nameError=$chainError -bor [Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch
        Assert-Workflow (-not [DssfHttpV3]::IsExpiryOnly($url,$nameError,$timeOnly,$starts,$ends,$now)) "$label expiry does not hide hostname mismatch"
        Assert-Workflow (-not [DssfHttpV3]::IsExpiryOnly($url,$chainError,$timeOnly,[DateTime[]]@($now.AddDays(1)),[DateTime[]]@($now.AddYears(1)),$now)) "$label future certificates are rejected"
        Assert-Workflow ($source.Contains('q.AllowAutoRedirect = false')) "$label expiry permission is not carried through redirects"
        Assert-Workflow ($source -notmatch '--ignore-certificate-errors') "$label does not disable browser certificate validation"
        foreach($name in 'Get-DscFindingsSummary','Request-ConsoleReview','Get-DscOverallState','Get-DssSha256','Test-DscLiveResponse','Test-IsLive','Test-JavaLatest','Update-JavaOffer','Invoke-OptionalJavaUpdate','Prepare-DscInstaller','Get-DssPackageFromWeb','Invoke-StartupSequence','Start-Console','Invoke-GuiTest') {
            . ([scriptblock]::Create((Read-WorkflowFunction $ast $name)))
        }
        $Cfg=@{DssVersion='4.1.8';IsLiveUrl=$url;OpenReport=$false;AllowDssDownload=$false;PackageUrl='';PackageSha256=''}
        $script:FixtureResponse=@{Ok=$true;Body='success. DSC Signer Service version : 4.1.8';ExpiredAccepted=$false;CertificateTrusted=$true}
        function Invoke-IsLive {return $script:FixtureResponse}
        function Get-CertReason {param($raw,$ssl)'Certificate error'}
        Assert-Workflow ((Test-IsLive).Pass -and -not (Test-IsLive).Warn) "$label trusted success passes"
        $script:FixtureResponse.ExpiredAccepted=$true
        $r=Test-IsLive
        Assert-Workflow ($r.Pass -and $r.Warn -and -not $r.Fixable -and $r.ExpiredAccepted) "$label expired success is a non-blocking warning, not a mandatory repair"
        $script:FixtureResponse=@{Ok=$false;Body='success 4.1.8';Kind='TrustFailure';SslErrors='RemoteCertificateNameMismatch'}
        Assert-Workflow (-not (Test-IsLive).Pass) "$label other certificate errors fail"
        foreach($bad in 'version 4.1.8','unsuccessful 4.1.8','success 4.1.80','success 4.1.7') {
            $script:FixtureResponse=@{Ok=$true;Body=$bad;ExpiredAccepted=$false}
            Assert-Workflow (-not (Test-IsLive).Pass) "$label rejects malformed or wrong-version response: $bad"
        }
        $script:JavaInfo=@{Major=8;Update=451;Is64=$true;Name='Java 8 Update 451'}
        $script:UpdateFetches=0;$script:UiJavaOffer=$null
        function Get-InstalledJava {return [pscustomobject]$script:JavaInfo}
        function Get-JavaLatest {$script:UpdateFetches++;@{Update=999;Url='fixture'}}
        function Say {param($text,$color)}
        function Write-DscEvent {param($level,$operation,$data)}
        function Write-DscError {param($record,$operation)}
        $installed=Test-JavaLatest
        Assert-Workflow ($installed.Pass -and -not $installed.Warn -and $script:UpdateFetches -eq 0) "$label installed Java check does not fetch or require updates"
        $script:JavaInfo.Is64=$false
        Assert-Workflow (-not (Test-JavaLatest).Pass) "$label unsuitable Java still fails its requirement"
        $script:JavaInfo.Is64=$true
        $script:Results=@{'1'=@{Status='OK'};'7'=@{Status='OK'}}
        Update-JavaOffer
        Assert-Workflow ($script:JavaUpdateOffer.Available -and $script:UpdateFetches -eq 1 -and $Results['1'].Status -eq 'OK') "$label available update leaves working Java passed"
        $script:InstalledUpdates=0;$IsAdmin=$true;$script:ByNo=@{1=@{R=@{}}}
        function Install-JavaLatest {param($r)$script:InstalledUpdates++}
        [void](Invoke-OptionalJavaUpdate)
        Assert-Workflow ($script:InstalledUpdates -eq 0) "$label optional Java update needs explicit selection"
        [void](Invoke-OptionalJavaUpdate -Confirmed)
        Assert-Workflow ($script:InstalledUpdates -eq 1) "$label explicit optional update is routed separately"
        $Results['7'].Status='FAIL';$script:UpdateFetches=0
        Update-JavaOffer
        Assert-Workflow (-not $script:JavaUpdateOffer.Available -and $script:UpdateFetches -eq 0) "$label broken Java does not offer an optional upgrade first"

        # Package preparation and download capability tests; files contain fixture bytes only.
        $CheckOnly=$false;$script:DiagnosticsOnly=$false;$script:Results=@{'3'=@{Status='FAIL'}}
        $script:PackageReads=0;$script:Downloads=0;$script:SourcePresent=$false;$script:ValidPackage=$true
        function Add-Detail {param($r,$text)}
        function Find-DssPackageSource {$script:PackageReads++;if($script:SourcePresent){@{Kind='msi';Path='fixture.msi'}}}
        function Get-DssPackageMsi {'fixture.msi'}
        function Test-PackageValid {param($p)@{Ok=$script:ValidPackage;Text='fixture validation'}}
        Assert-Workflow (-not (Prepare-DscInstaller) -and $script:PackageReads -eq 1) "$label local-package edition does not attempt DSS download"
        $CheckOnly=$true;$script:PackageReads=0
        Assert-Workflow (-not (Prepare-DscInstaller) -and $script:PackageReads -eq 0) "$label check-only does not prepare/download installers"
        $CheckOnly=$false;$script:SourcePresent=$true
        Assert-Workflow (Prepare-DscInstaller) "$label validates an available local installer"
        $script:ValidPackage=$false
        Assert-Workflow (-not (Prepare-DscInstaller)) "$label invalid package is rejected"
        $Results['3'].Status='OK';$script:PackageReads=0
        Assert-Workflow (-not (Prepare-DscInstaller) -and $script:PackageReads -eq 0) "$label working installation needs no package"
        function Get-DownloadsFolder {Join-Path $fixtureRoot 'Downloads'}
        function Confirm-DssDownload {return $true}
        function Get-WebFileResume {param($url,$outFile)$script:Downloads++;[IO.File]::WriteAllBytes($outFile,[byte[]]@(0x50,0x4B,3,4,0,0,0,0));@{Ok=$true}}
        function Test-PackagePath {param($p)@{Kind='zip';Path=$p;Version='4.1.8'}}
        function Get-FileHash {param($LiteralPath,$Algorithm)$sha=[Security.Cryptography.SHA256]::Create();try{@{Hash=[BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($LiteralPath))).Replace('-','')}}finally{$sha.Dispose()}}
        $TestMode=$false;$Cfg.AllowDssDownload=$false;$Cfg.PackageUrl='https://example.invalid/fixture.zip'
        $script:DscSession=@{SessionId=[guid]::NewGuid().ToString('N')}
        Assert-Workflow (-not (Get-DssPackageFromWeb) -and $script:Downloads -eq 0) "$label disabled DSS capability ignores a supplied URL"
        $Cfg.AllowDssDownload=$true;$script:ValidPackage=$true
        Assert-Workflow (Get-DssPackageFromWeb) "$label downloader validates fixture package"
        Assert-Workflow ($script:PkgOverride.StartsWith((Join-Path $fixtureRoot 'Downloads'))) "$label downloaded package stays under Downloads"
        $Cfg.PackageSha256=('0'*64);$threw=$false
        try{[void](Get-DssPackageFromWeb)}catch{$threw=$true}
        Assert-Workflow $threw "$label mismatched package hash is rejected"
        $quarantine=Join-Path (Get-DownloadsFolder) ('DSC-Signer-4.1.8\DSS-4.1.8-' + $script:DscSession.SessionId + '-source1.zip.rejected')
        Assert-Workflow (Test-Path -LiteralPath $quarantine) "$label hash-rejected archive cannot be rediscovered as an installer ZIP"
        $Cfg.PackageSha256='';$script:ValidPackage=$false;$threw=$false
        try{[void](Get-DssPackageFromWeb)}catch{$threw=$true}
        Assert-Workflow $threw "$label downloaded content validation is mandatory"
        $expectedDownload=$true
        Assert-Workflow ($source.Contains('AllowDssDownload    = $'+$expectedDownload.ToString().ToLowerInvariant())) "$label offers permission-based DSS downloads"
        Assert-Workflow ($source.Contains('if ($Cfg.AllowDssDownload -and $env:DSSF_PKGURL)')) "$label inherited URL cannot enable an unsupported download"
        Assert-Workflow ($source.Contains("`$Cfg.RequiredDssPath = 'C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe'")) "$label checks the required Program Files path"
        Assert-Workflow ($source.Contains('another installation at') -and -not $source.Contains('$installed = $true; $exe = $other')) "$label alternate path does not count as the required installation"

        # Run actual GUI/console dispatchers with diagnostic, browser and preparation fixtures.
        function Reset-WorkflowFixture([bool]$LivePass) {
            $script:FixtureLive=$LivePass;$script:Trace=@();$script:DscSession=[ordered]@{};$script:UiRow=$null
            $script:Results=[ordered]@{};$script:Defs=@();$script:ByNo=@{}
            foreach($no in 1..10){$r=[pscustomobject]@{No=$no;Status='PENDING';Value='';Actions=@();Advice=''};$d=@{No=$no;R=$r;Tested=$false};$script:Results["$no"]=$r;$script:Defs+=$d;$script:ByNo[$no]=$d}
        }
        function Open-StartupBrowser {$script:Trace+='browser';return $true}
        function Invoke-AllTests {param([int[]]$Nos)foreach($no in $Nos){$script:Trace+="check$no";$script:Results["$no"].Status=$(if($no -eq 4 -and -not $script:FixtureLive){'FAIL'}else{'OK'})}}
        function Prepare-DscInstaller {$script:Trace+='prepare';return $false}
        function Update-JavaOffer {$script:Trace+='update-indicator'}
        function Get-DssProcesses {$script:Trace+='process';@()}
        function Show-Row {param($r)}
        function Save-Results {$script:Trace+='save';'fixture-report.html'}
        function Invoke-InstallerCheckConsole {$script:Trace+='installer-choice'}
        function Get-Fixable {@()}
        function Get-Failed {@()}
        function Ask {param($text,$valid,$default)$default}
        function Clear-Host {}
        function Set-Busy {param($busy)}
        function Update-Summary {}
        $expected='browser,check4,check3,check5,check7,check1,check2,prepare,update-indicator,process,check6,check8,check9,check10'
        Reset-WorkflowFixture $true
        Assert-Workflow ((Invoke-StartupSequence -OpenBrowser) -and ($script:Trace -join ',') -eq $expected) "$label successful isLive still completes the requested order"
        Reset-WorkflowFixture $false
        [void](Invoke-StartupSequence -OpenBrowser)
        Assert-Workflow (($script:Trace -join ',') -eq $expected) "$label failed isLive also follows the same complete order"
        $TestMode=$true;$CheckOnly=$false;$IsAdmin=$false;$script:Handoff=$null
        Reset-WorkflowFixture $true
        Start-Console
        Assert-Workflow (($script:Trace -join ',') -eq ($expected+',save')) "$label console continues after healthy isLive"
        Reset-WorkflowFixture $true;$CheckOnly=$true
        Start-Console
        Assert-Workflow (($script:Trace -join ',') -eq (($expected -replace '^browser,','')+',save')) "$label check-only has no browser or installer prompts"
        $script:G=@{Txt=(New-Object Text.StringBuilder);List=@{Items=@()}}
        Reset-WorkflowFixture $true
        Invoke-GuiTest
        Assert-Workflow (($script:Trace -join ',') -eq ($expected+',save')) "$label GUI uses identical complete sequence"
        Assert-Workflow ($source.Contains("'Update Java (optional)'") -and $source.Contains('$G.JavaTimer.Add_Tick')) "$label GUI has an optional flashing Java update control"
        Assert-Workflow ($source.Contains("'Browser exception ...'") -and $source.Contains('Show-SignerCertificateHelp -UseGui')) "$label GUI has signer-only browser exception help"
    } $ast $source $file.Name $file.Directory.Name $fixtureRoot
}
if((Split-Path -Leaf $repositoryRoot) -eq 'DSC-FIXR') {
    $online=[IO.File]::ReadAllText((Join-Path $repositoryRoot 'install.ps1'))
    Assert-Workflow ($online.Contains("`$downloads = Join-Path (Get-DownloadsFolder) 'DSC-Signer-4.1.8'")) 'FIXR explicit package preparation also uses Downloads'
    Assert-Workflow ($online.Contains("`$env:DSSF_PKGURL = `$(if (`$NoPackage) { '' } else { `$PackageUrl })")) 'FIXR NoPackage disables subsequent DSS downloads'
}
Write-Host "STARTUP TOTAL PASS: $script:WorkflowPass; PowerShell $($PSVersionTable.PSVersion)"
