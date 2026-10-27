# DSC-FIXER - Native PowerShell test edition

> Current local build: **2026.10.27.3**. All editions now support permission-based DSS installer downloads. Earlier local-package-only capability notes below are superseded by the Download permission and repository backups section.

Run in Windows PowerShell:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 3072
irm 'https://raw.githubusercontent.com/girishtiwari007/DSC-FIXER/main/install.ps1' | iex
```

Choose 1 for the PowerShell console, 2 for Windows popups, 3 to redraw the menu, or 4 to exit. Closing a mode returns to the menu. For repairs, open Windows PowerShell as Administrator first. Windows popups require STA (Windows PowerShell normally uses it).

The script runs directly in the current session and does not download or launch a batch application. It does not change antivirus settings or execution policy, and is not guaranteed to be accepted by Trellix. Ask IT to review any block. Logs, reports, backups and approved installer operations can still write files. The script is unsigned.

Validated in Windows PowerShell 5.1: syntax, no BOM, menu/exit, console/check/GUI routing, WinForms construction, and no automatic elevation. Diagnostics and repairs were stubbed during routing tests; actual repairs, installer execution, network launch and Trellix acceptance were not certified.

This update affects only DSC-FIXER. DSC-FIX and DSC-FIXR remain unchanged.

---

# DSC-FIXER

## Session logs and GitHub reports (2026.10.26.1)

Each launch keeps a unique session under `%LOCALAPPDATA%\DSC-Signer-Fixer\sessions` (TEMP fallback). The location is printed on exit. Application diagnostics and backups now use this session folder rather than the previous ProgramData folder. Launcher sessions and application sessions are separate.

- `events.jsonl`: local timestamps, caught exceptions with messages/stack traces, diagnostic failures, attempted repairs and installer exit codes.
- `session.json`: tool version, session ID, mode, latest check statuses, action counts, error groups and unresolved-check follow-ups.
- `github-report.md`: allowlisted preview suitable for optional GitHub submission. Application sessions also retain `fix-log.txt`, `result.json`, HTML reports and backups.

Use **Report error ...** or **Suggest improvement ...** in the dashboard. Console mode offers the same choices after a run; the startup menu contains only options 1-4 and displays the session-log folder. Check-only mode never prompts to report.

To report a saved session later (including an offline session or launcher failure), download `Report-Session.ps1` from this repository and run:

```powershell
.\Report-Session.ps1 -SessionDirectory 'C:\path\to\saved-session'
.\Report-Session.ps1 -SessionDirectory 'C:\path\to\saved-session' -Kind Improvement -Gui
```

The preview excludes arbitrary exception messages, stacks, paths, usernames, machine names, logs and certificate contents. Only tool version, check numbers/statuses/action counts and exception types/line numbers are included. Local diagnostic files may contain sensitive system details: do not attach them to public issues without review.

**Nothing is uploaded automatically.** Search existing issues by the generated fingerprint and add information to a matching issue, or open a prefilled new issue. Review and submit in your browser using your own GitHub login. The tool stores no GitHub credentials. If offline or the browser fails, the Markdown preview remains available. Fingerprints assist manual grouping; issues are not merged automatically. The GitHub repository must have Issues enabled.

Logging cannot capture a script blocked before execution, power loss, or forcible process termination. A last saved `Running` session can indicate an interrupted run. Expected fallback exceptions can appear even if the final checks pass; consult check results as well as error counts.

### Repair safety updates

Replacement MSI availability/content/version is checked before DSS is stopped or old versions are removed. Installer failures stop the operation; restart-required outcomes are reported. Offline checks still require 64-bit Java. FIXR online startup requires a current checksum manifest and verifies downloaded or cached tool bytes before launching.


### Release regression checks

Run `powershell.exe -NoProfile -STA -File .\tests\Test-Release.ps1` where local policy permits. Tests use isolated TEMP fixtures, mocked repair operations, and harmless child processes to check exit/timeout handling. They parse scripts, verify payload/checksum consistency, exercise failure paths and report privacy, and construct WinForms controls without showing a dashboard or running repairs. They do not certify real installation, signing, UAC, network availability or antivirus acceptance. Temporary test logs are retained for inspection. Execution policy is not changed.


## Ordered workflow (2026.10.26.3; local testing)

Both GUI and PowerShell console use the same sequence, continuing even when isLive succeeds:

1. Open isLive and require `success. DSC Signer Service version : 4.1.8`. A date-expiry-only certificate alert is a non-blocking warning for exactly `https://eoffsigner.eoffice.gov.in:55101/check/isLive`; name mismatch, unknown roots and other errors are not ignored.
2. Verify `C:\Program Files\Digital Signer Service\4.1.8\Digital Signer Service.exe` exists. Another installation directory does not satisfy this check.
3. Check PATH/environment cleanup; selected repairs keep backups.
4. Check Java execution and suitable installed Java. Keep working Java without an update prompt.
5. Check port 55101 and identify its listener.
6. Where installation/repair is needed, prepare and automatically validate the package. Only FIXR's online/batch edition supports downloading DSS, using a session-named package under Downloads\DSC-Signer-4.1.8. DSC-FIX, DSC-FIXER and FIXR native remain local-package editions; inherited downloader variables cannot enable a DSS download. Installation still requires selecting a repair. Check-only mode does not download.
7. Indicate an available Java update as optional: a flashing GUI button or highlighted console option. No upgrade is included in Fix All for working Java.
8. Complete process, hosts and browser checks; then offer selected repairs and optional reporting.

The Browser exception button provides guidance for Advanced/Proceed or Add Exception for the signer address where the browser offers it. It does not automate interstitial clicks, bypass browser-enforced restrictions, disable validation globally or store browser-wide trust exceptions. Accepted expiry warnings remain visible in reports/logs.

Run `tests\Test-Release.ps1` for the release regression suite and `tests\Test-StartupSequence.ps1` for the ordered-workflow suite. These use fixtures; real installation/signing/browser exceptions need local testing. No commits or pushes were made.


## Live-test corrections (2026.10.26.4)

Visible check numbers now run 1–10 in workflow order; stable internal IDs remain in logs. GUI rows update by their identity instead of the old list index. isLive readiness is independent of supplemental issues: confirmed success, including the accepted signer expiry warning, displays WORKING. Other issues remain visible in their own rows; unavailable probes are warnings, not evidence of service failure. Java version output is read from both native process streams. Empty browser output is explicitly unverified and does not propose an automatic repair.


## Diagnostics and review (2026.10.27.1)

The GUI and console identify their edition and build. Signer service health and other-check findings have separate summaries. Initial checks are diagnostics-only: no repair selection modal, installer prompt, installer preparation/download or repair runs automatically. Select **Review proposed fixes** (console: R) to inspect plans and prepare a needed installer within the edition's existing capability. Then explicitly choose Apply; no repair checkbox is preselected. Elevated restarts return to diagnostics/review rather than automatically resuming repairs. Explicit installer preparation and optional Java update controls remain user-initiated actions. No commits or pushes have been made.


## Download permission and repository backups (2026.10.27.3)

All editions now offer an explicit DSS 4.1.8 download permission prompt for installation fix #2, following the user's revised instruction. Initial diagnostics still do not download installers. Approving the download saves it under Downloads, checks any supplied checksum, validates its content/version and maps the extracted MSI automatically. The installation is still a separate reviewed action. Declining or failing the download never stops/uninstalls DSS and does not automatically open the ZIP/MSI/folder mapping dialog. Get DSS installer retries permission; manual local packages remain available when downloads are explicitly disabled with DSSF_NO_PACKAGE=1 (FIXR launcher: -NoPackage).

Repository source files are backed up before development edits. No backup or snapshot of the user's DSS installation is created or required. Download permission, package validation/mapping and reviewed installation remain available.

Before editing repository sources, always create and verify a timestamped backup outside the repository, excluding Git metadata; never overwrite older backups. Keep a file/hash inventory. No commit or push without explicit user approval.


## Backup scope clarification (2026.10.27.3)

The user's backup instruction applies only to repository source files before editing. The user-side DSS installation-backup function and prerequisite have been removed from GUI/console editions. Existing archived backups are not deleted. Download permission, automatic validation/mapping and the reviewed installation/repair flow are unchanged. The historical test filename Test-DownloadBackup.ps1 now covers downloads and verifies that installation snapshots are absent. Standard PATH/hosts repair copies remain as before. No commits or pushes were made.
