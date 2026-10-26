# DSC-FIXER - Native PowerShell test edition

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

Use **Report error ...** or **Suggest improvement ...** in the dashboard. Console mode offers the same choices after a run; native menus also offer options 5 and 6. Check-only mode never prompts to report.

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
