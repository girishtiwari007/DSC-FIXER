# Publisher signing

Status: unsigned. No code-signing certificate was found when these instructions
were added. Copyright notices do not provide signature verification or secrecy.

Use a certificate issued for code signing by your organization or a certificate
authority, with its private key available to the publisher. Do not share the key.
Obtain the timestamp service URL from that issuer. Do not disable execution policy,
install arbitrary trust roots, or use an automatically created self-signed certificate.

After final edits and testing, run in Windows PowerShell on the publishing machine:

```powershell
$cert = Get-Item 'Cert:\CurrentUser\My\YOUR_CODE_SIGNING_CERTIFICATE_THUMBPRINT'
$files = @('D:\github\DSC-FIXER\install.ps1', 'D:\github\DSC-FIXER\Report-Session.ps1')
foreach ($file in $files) {
    $signature = Set-AuthenticodeSignature -LiteralPath $file -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'YOUR_ISSUER_TIMESTAMP_URL'
    if ($signature.Status -ne 'Valid') { throw "Signing failed: $file ($($signature.Status))" }
}
$files | ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_ } |
    Format-List Path, Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

Replace both placeholders before running. A machine-store certificate may require
the corresponding LocalMachine certificate path and authorized key access.
Back up repository files before signing; signing changes the scripts. Run the
release checks after signing and do not edit signed files without signing again.

For distribution, download the signed file, verify Get-AuthenticodeSignature reports
Valid and confirm the expected publisher/certificate using a separately trusted
record, then execute the saved file under the organization's normal policy.
The existing irm | iex command evaluates text and does not enforce Authenticode
verification of the downloaded file. A Valid signature alone does not establish
that the signer is the publisher you intended to trust.

Signing detects changes and identifies the signer; it cannot hide the source.
Public GitHub source remains viewable and forkable under GitHub's terms.

References:
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-authenticodesignature
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository