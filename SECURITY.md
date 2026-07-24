# Security Policy

SSD Watcher reads filesystem metadata and database counters, so privacy and
update integrity are part of its security boundary.

## Supported versions

The latest public release receives security fixes. During the initial `0.1.x`
series, fixes are not backported to older releases.

## Reporting

Please do not open a public issue for a vulnerability that could expose file
contents, bypass update verification, execute code, or modify user data. Use
GitHub's
[private vulnerability reporting](https://github.com/Takhoffman/ssd-watcher/security/advisories/new)
for this repository. Include the app version, macOS version, reproduction
steps, and expected impact. Do not include real credentials, prompt history, or
an unredacted agent database.

The maintainer will acknowledge a complete report as soon as practical, keep
the reporter informed while it is investigated, and coordinate disclosure
after a fix is available. Please allow reasonable time for a response before
publishing details.

## Release integrity

Public releases are Developer ID signed, Apple notarized, and distributed
through a Sparkle feed protected by EdDSA signatures. The Sparkle private key,
Developer ID private key, and notarization credentials must never be committed
to this repository.
