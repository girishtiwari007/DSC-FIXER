# Copyright (c) 2026 Girish Tiwari. All rights reserved.
# Use is subject to LICENSE.txt. This notice does not conceal source code.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SessionDirectory, [ValidateSet('Error','Improvement')][string]$Kind = 'Error', [switch]$Gui)
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw 'Organization policy restricts this session. Ask IT to review.' }
# Session logging is embedded so each published entry point remains self-contained.
function Initialize-DscSession([string]$Repository, [string]$ModeName) {
    $script:DscSession = [ordered]@{
        Schema = 1; ToolVersion = '2026.10.27.3'; Repository = $Repository
        SessionId = [guid]::NewGuid().ToString('N'); StartedUtc = [DateTime]::UtcNow.ToString('o')
        UpdatedUtc = ''; Mode = $ModeName; PowerShell = $PSVersionTable.PSVersion.ToString()
        State = 'Running'; ErrorCount = 0; Checks = @(); Improvements = @()
    }
    $script:DscLoggingFailed = $false
    $script:DscErrorKeys = @{}
    $script:DscErrorGroups = @{}
    $script:DscSessionDirectory = $null
    $roots = @()
    if ($env:DSSF_TESTROOT) { $roots = @((Join-Path $env:DSSF_TESTROOT 'out')) }
    else {
        if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'DSC-Signer-Fixer\sessions' }
        if ($env:TEMP) { $roots += Join-Path $env:TEMP 'DSC-Signer-Fixer\sessions' }
    }
    foreach ($root in $roots) {
        try {
            $dir = Join-Path $root ((Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '_' + $script:DscSession.SessionId)
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::WriteAllText((Join-Path $dir 'events.jsonl'), '', (New-Object Text.UTF8Encoding $false))
            $script:DscSessionDirectory = $dir
            break
        } catch { }
    }
    if (-not $script:DscSessionDirectory) { throw 'Cannot create a local session log. Check write access to LOCALAPPDATA or TEMP; no repairs were started.' }
    Write-DscEvent 'Info' 'Session started' @{ Mode = $ModeName }
    Save-DscSession
}
function Write-DscEvent([string]$Level, [string]$Operation, $Data) {
    if (-not $script:DscSessionDirectory) { return }
    try {
        $event = [ordered]@{ TimeUtc = [DateTime]::UtcNow.ToString('o'); SessionId = $script:DscSession.SessionId; Level = $Level; Operation = $Operation; Data = $Data }
        $json = ConvertTo-Json -InputObject $event -Depth 8 -Compress
        [IO.File]::AppendAllText((Join-Path $script:DscSessionDirectory 'events.jsonl'), $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false))
    } catch {
        if (-not $script:DscLoggingFailed) { Write-Warning 'Session logging failed. Check free disk space and folder permissions.' }
        $script:DscLoggingFailed = $true
    }
}
function Write-DscError($Record, [string]$Operation = 'Unhandled exception', [Nullable[int]]$ExitCode = $null) {
    if (-not $script:DscSession) { return }
    $type = 'System.Exception'; $message = [string]$Record; $stack = ''; $line = 0; $errorId = ''
    if ($Record -is [Management.Automation.ErrorRecord]) {
        $type = $Record.Exception.GetType().FullName; $message = $Record.Exception.Message
        $stack = $Record.ScriptStackTrace; $line = $Record.InvocationInfo.ScriptLineNumber
        $errorId = $Record.FullyQualifiedErrorId
    } elseif ($Record -is [Exception]) { $type = $Record.GetType().FullName; $message = $Record.Message; $stack = $Record.StackTrace }
    $key = "$Operation|$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Record))"
    # The same caught ErrorRecord may reach the session trap; log it only once.
    if ($script:DscErrorKeys.ContainsKey($key)) { return }
    $script:DscErrorKeys[$key] = $true
    $script:DscSession.ErrorCount++
    # Only type and numeric line enter the public report. Messages and stack traces remain local.
    $publicKey = "$type|$line|$ExitCode"
    if (-not $script:DscErrorGroups.ContainsKey($publicKey)) {
        $script:DscErrorGroups[$publicKey] = [ordered]@{ Type = $type; Line = $line; Count = 0; ExitCode = $ExitCode }
    }
    $script:DscErrorGroups[$publicKey].Count++
    Write-DscEvent 'Error' $Operation @{ Type = $type; Message = $message; StackTrace = $stack; Line = $line; ErrorId = $errorId; ExitCode = $ExitCode }
    Save-DscSession
}
function Save-DscSession($CheckResults, [string]$State = '') {
    if (-not $script:DscSessionDirectory) { return }
    try {
        if ($null -ne $CheckResults) {
            $script:DscSession.Checks = @($CheckResults.Values | ForEach-Object {
                [ordered]@{ No = $_.No; Status = $_.Status; ActionsAttempted = @($_.Actions).Count; Advice = $_.Advice }
            })
        }
        if ($State) { $script:DscSession.State = $State }
        $script:DscSession.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
        $script:DscSession.Improvements = @($script:DscSession.Checks | Where-Object { $_.Status -in 'FAIL','SKIP','WARN','PENDING' } | ForEach-Object {
            "Review check $($_.No) ($($_.Status)); see the local diagnostic report."
        })
        $doc = [ordered]@{}
        foreach ($key in $script:DscSession.Keys) { $doc[$key] = $script:DscSession[$key] }
        $doc.Errors = @($script:DscErrorGroups.Values)
        $json = ConvertTo-Json -InputObject $doc -Depth 8
        $file = Join-Path $script:DscSessionDirectory 'session.json'
        [IO.File]::WriteAllText(($file + '.tmp'), $json, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath ($file + '.tmp') -Destination $file -Force -ErrorAction Stop
        $report = Get-DscPublicReport
        [IO.File]::WriteAllText((Join-Path $script:DscSessionDirectory 'github-report.md'), $report.Body, (New-Object Text.UTF8Encoding $false))
    } catch {
        if (-not $script:DscLoggingFailed) { Write-Warning 'Could not save the session summary. Existing logs have been retained.' }
        $script:DscLoggingFailed = $true
    }
}
function Get-DscPublicReport([ValidateSet('Error','Improvement')][string]$Kind = 'Error') {
    # An allowlist is safer than trying to redact arbitrary exception messages or logs.
    $repo = [string]$script:DscSession.Repository
    if ($repo -notin @('girishtiwari007/DSC-FIX','girishtiwari007/DSC-FIXR','girishtiwari007/DSC-FIXER')) { throw 'Unsupported report repository.' }
    $version = [string]$script:DscSession.ToolVersion
    if ($version -notmatch '^\d{4}\.\d{2}\.\d{2}\.\d+$') { throw 'Invalid report version.' }
    $checks = @($script:DscSession.Checks | Sort-Object { [int]$_.No } | Select-Object -First 10 | ForEach-Object {
        $no = [int]$_.No; $status = [string]$_.Status
        if ($no -ge 1 -and $no -le 10 -and $status -in 'OK','FIXED','WARN','FAIL','SKIP','NA','NOTRUN','PENDING') { "Check ${no}: $status; attempted actions: $([int]$_.ActionsAttempted)" }
    })
    $errors = @($script:DscErrorGroups.Values | Sort-Object Type,Line | Select-Object -First 12 | ForEach-Object {
        if ($_.Type -match '^[A-Za-z][A-Za-z0-9_.+`]{0,160}$') {
            $code = $(if ($null -ne $_.ExitCode) { "; exit code $([int]$_.ExitCode)" } else { '' })
            "$($_.Type) at line $([int]$_.Line)$code (count $([int]$_.Count))"
        }
    })
    $signature = "$repo|$version|$Kind|$($checks -join '|')|$($errors -join '|')"
    # Counts do not affect grouping between sessions with the same underlying problem.
    $signature = $signature -replace '; attempted actions: \d+', '' -replace '\(count \d+\)', ''
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature))).Replace('-','').Substring(0,16)).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $body = @(
        "## DSC $Kind report", "Tool version: $version", "Fingerprint: dsc-$fingerprint", ''
        '### Check summary', $(if ($checks.Count) { $checks -join "`n" } else { 'No checks completed.' }), ''
        '### Exceptions', $(if ($errors.Count) { $errors -join "`n" } else { 'No exceptions recorded.' }), ''
        '### Expected result / improvement', 'Describe what should happen here.', ''
        '### Steps to reproduce', 'Add steps here. Do not include personal information, passwords, tokens or certificate files.', ''
        'Generated from an allowlist. Exception messages, stack traces, file paths, logs, machine/user names and certificate contents are excluded.'
    ) -join "`n"
    return @{ Repository = $repo; Title = "[DSC $Kind] dsc-$fingerprint ($version)"; Body = $body; Fingerprint = $fingerprint }
}
function Show-DscGitHubReport([ValidateSet('Error','Improvement')][string]$Kind = 'Error', [switch]$UseGui) {
    $report = Get-DscPublicReport $Kind
    $reportPath = Join-Path $script:DscSessionDirectory 'github-report.md'
    [IO.File]::WriteAllText($reportPath, $report.Body, (New-Object Text.UTF8Encoding $false))
    $searchUrl = 'https://github.com/' + $report.Repository + '/issues?q=' + [Uri]::EscapeDataString('is:issue "dsc-' + $report.Fingerprint + '"')
    $newUrl = 'https://github.com/' + $report.Repository + '/issues/new?title=' + [Uri]::EscapeDataString($report.Title) + '&body=' + [Uri]::EscapeDataString($report.Body)
    if ($UseGui) {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $dialog = New-Object Windows.Forms.Form
        try {
            $dialog.Text = 'Preview GitHub report'; $dialog.Size = New-Object Drawing.Size(760,620); $dialog.StartPosition = 'CenterScreen'
            $text = New-Object Windows.Forms.TextBox; $text.Multiline = $true; $text.ReadOnly = $true; $text.ScrollBars = 'Vertical'; $text.Dock = 'Fill'; $text.Text = $report.Body.Replace("`n","`r`n")
            $bar = New-Object Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Bottom'; $bar.Height = 72
            $hint = New-Object Windows.Forms.Label; $hint.Dock = 'Top'; $hint.Height = 52; $hint.Text = "Local preview: $reportPath`r`nSearch for this fingerprint first. GitHub opens in your browser; review and submit there. Offline? Keep this file and submit later."
            $search = New-Object Windows.Forms.Button; $search.Text = 'Find existing'; $search.Width = 130
            $create = New-Object Windows.Forms.Button; $create.Text = 'Open new issue'; $create.Width = 140
            $close = New-Object Windows.Forms.Button; $close.Text = 'Close'; $close.Width = 100
            $search.Add_Click({ try { Start-Process $searchUrl -ErrorAction Stop } catch { Write-DscError $_ 'Open GitHub search'; [void][Windows.Forms.MessageBox]::Show('Browser unavailable. The preview is saved locally.') } }.GetNewClosure())
            $create.Add_Click({ try { Start-Process $newUrl -ErrorAction Stop } catch { Write-DscError $_ 'Open GitHub issue'; [void][Windows.Forms.MessageBox]::Show('Browser unavailable. The preview is saved locally.') } }.GetNewClosure())
            $close.Add_Click({ $dialog.Close() }.GetNewClosure())
            $bar.Controls.AddRange(@($search,$create,$close)); $dialog.Controls.AddRange(@($text,$hint,$bar)); [void]$dialog.ShowDialog()
        } finally { $dialog.Dispose() }
    } else {
        Write-Host $report.Body
        Write-Host "Preview saved: $reportPath"
        $choice = Read-Host '[S] Search existing issues  [N] Open new issue  [Enter] Keep locally'
        if ($choice -match '^(?i)s$') { Start-Process $searchUrl -ErrorAction Stop }
        elseif ($choice -match '^(?i)n$') { Start-Process $newUrl -ErrorAction Stop }
    }
}

$script:DscSessionDirectory = (Resolve-Path -LiteralPath $SessionDirectory -ErrorAction Stop).ProviderPath
$saved = Get-Content -LiteralPath (Join-Path $script:DscSessionDirectory 'session.json') -Raw -ErrorAction Stop | ConvertFrom-Json
if ($saved.Schema -ne 1) { throw 'Unsupported session schema.' }
$script:DscSession = [ordered]@{}
foreach ($property in $saved.PSObject.Properties) { $script:DscSession[$property.Name] = $property.Value }
$script:DscErrorGroups = @{}
foreach ($errorGroup in $saved.Errors) { $script:DscErrorGroups["$($errorGroup.Type)|$($errorGroup.Line)|$($errorGroup.ExitCode)"] = $errorGroup }
$script:DscErrorKeys = @{}
$script:DscLoggingFailed = $false
Show-DscGitHubReport -Kind $Kind -UseGui:$Gui
