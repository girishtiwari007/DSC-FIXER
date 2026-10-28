# Plan mapping

Plan 1: D:\github\DSC-FIXER — Windows PowerShell troubleshooter. Entry: install.ps1.

Plan 2: D:\github\nrdscfix — static website. Entry: index.html at repository root.
Its online launcher runs the published Plan 1 script; its alternate bundled copy
is refreshed from tested local Plan 1 source. Do not maintain separate repair logic.

Code/security review is in SECURITY-REVIEW.md. The current review identified
unresolved remote-script and installer-authentication release risks. Functional
test success does not mean those risks are fixed.

No commit or push is authorized by this mapping.
