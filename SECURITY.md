# Security Policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems. Instead,
report them privately through the contact form on the website:

**https://filelore.netlify.app#contact**

Include the platform (macOS/Windows), app version, and enough detail to
reproduce the issue. I'll acknowledge and investigate as quickly as a solo
maintainer can.

## Auto-update security model

macOS releases are delivered through **Sparkle** and are **EdDSA-signed**:
the app verifies the signature of every update before installing it. The
**private signing key is not in this repository** and never will be — only
the public key ships in the app bundle. If the private key were ever lost or
compromised, existing installs would be unable to verify updates, so it is
kept offline and backed up outside the repo.

The Windows build currently has **no auto-updater and is not code-signed** —
this is a known gap on the roadmap (Velopack auto-update, Authenticode code
signing). Download Windows releases only from the official site:
https://filelore.netlify.app

## Scope

FileLore stores notes as plain JSON in filesystem metadata (xattr / NTFS ADS)
on your own files. It has no network features beyond update checks on macOS
and collects no telemetry or personal data.
