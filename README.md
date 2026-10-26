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