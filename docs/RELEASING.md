# Releasing SSD Watcher

SSD Watcher ships one universal app bundle through two familiar paths: a
signed and notarized DMG from GitHub Releases, and a Homebrew Cask generated
from that same DMG. Sparkle uses a separately signed ZIP to provide secure
in-app updates.

## Security model

Every public build has three independent checks:

1. Developer ID signing lets macOS verify the app publisher.
2. Apple notarization lets Gatekeeper verify the distributed app and DMG.
3. Sparkle EdDSA signatures verify update archives, the appcast, and release
   notes before extraction.

The repository contains the Sparkle public key. Its private key stays in the
macOS Keychain or in encrypted GitHub Actions secrets.

## One-time local setup

The release machine needs Xcode, XcodeGen, and the Developer ID Application
certificate for team `KF4GF4J4K9`.

If signing reports `errSecInternalComponent`, the certificate is installed but
`codesign` cannot use its private key. In Keychain Access, select the `login`
keychain, open **My Certificates**, expand the Developer ID Application
certificate, open its private key, and add `/usr/bin/codesign` under **Access
Control**. macOS will ask for the login password for this one-time change.
Avoid selecting “Allow all applications” on a long-lived development Mac.

Store notarization credentials in Keychain. An App Store Connect API key is
preferred:

```sh
xcrun notarytool store-credentials SSDWatcherNotary \
  --key /secure/location/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_UUID
```

The Sparkle key was generated with Sparkle's `generate_keys` tool. Back it up
offline once:

```sh
/tmp/SSDWatcherDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
  -x /secure/offline/location/ssd-watcher-sparkle-private-key
```

That file is as sensitive as a password. Never add it to Git, cloud storage, a
release, or an issue.

## Local release

Add release notes at `release-notes/<version>.md`, then run:

```sh
NOTARYTOOL_PROFILE=SSDWatcherNotary scripts/release.sh 0.1.0
```

The script builds both Apple Silicon and Intel slices, signs and exports the
app, notarizes and staples it, creates the ZIP and DMG, signs the Sparkle feed,
generates the Homebrew Cask, and runs Gatekeeper verification. Upload every
file in `dist/` to a GitHub release tagged `v<version>`.

## GitHub Actions secrets

The release workflow expects:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `SPARKLE_PRIVATE_KEY`

`SPARKLE_PRIVATE_KEY` is the exact exported key-file content, not an additional
base64 encoding of it. Repository secrets must never be exposed to pull request
workflows.

The generated cask should be copied to a `homebrew-tap` repository at
`Casks/ssd-watcher.rb`. Users can then install and upgrade with:

```sh
brew install --cask Takhoffman/tap/ssd-watcher
brew upgrade --cask ssd-watcher
```
