# Security Policy

SSD Watcher reads filesystem metadata and database counters, so privacy and
update integrity are part of its security boundary.

Please do not open a public issue for a vulnerability that could expose file
contents, bypass update verification, execute code, or modify user data. Use
GitHub's private vulnerability reporting for this repository. Include the app
version, macOS version, reproduction steps, and expected impact.

Public releases are Developer ID signed, Apple notarized, and distributed
through a Sparkle feed protected by EdDSA signatures. The Sparkle private key,
Developer ID private key, and notarization credentials must never be committed
to this repository.
