# Security Policy

## Reporting a Vulnerability

If you find a security issue, please **do not open a public issue**. Report it via GitHub
[Private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
(Security tab → Report a vulnerability).

- Target initial response: within 5 business days
- Contact: contact@hugoconsulting.com

## Handling

This server deals with connection details to SAP systems (client secrets, etc.).

- **Never commit** `connections.json`.
- Connection and authentication details are not embedded in the distributed binary.
- For production (PRD) access, use a least-privilege service user and restrict the operation
  scope per landscape.

## Verifying a release

Every published binary is signed with sigstore (keyless) and carries a GitHub build provenance
attestation. Verify both before use — see "Verifying a download" in [README.md](README.md).
