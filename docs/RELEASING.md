# Releasing SSD Watcher

SSD Watcher ships one universal app bundle through two familiar paths: a
signed and notarized DMG from GitHub Releases, and a Homebrew Cask generated
from that same DMG. Sparkle uses a separately signed ZIP to provide secure
in-app updates.

The normal release path is GitHub Actions. Local release support exists as a
recovery path and for validating signing before the repository is public.

## Security model

Every public build has three independent checks:

1. Developer ID signing lets macOS verify the app publisher.
2. Apple notarization lets Gatekeeper verify the distributed app and DMG.
3. Sparkle EdDSA signatures verify update archives, the appcast, and release
   notes before extraction.

The repository contains the Sparkle public key. Its private key stays in the
macOS Keychain or in the protected `release` environment's encrypted GitHub
Actions secrets.

## One-time GitHub setup

Create these two public repositories without adding starter files:

- `Takhoffman/ssd-watcher`
- `Takhoffman/homebrew-tap`

Push this existing repository to `Takhoffman/ssd-watcher`. In its settings:

1. Enable Issues and private vulnerability reporting.
2. Protect `main`: require a pull request, require the **CI / test** check, and
   block force pushes and branch deletion.
3. Create an environment named `release`. Add a required reviewer if another
   trusted maintainer is available; otherwise use the environment as the
   dedicated home for release secrets.
4. Allow GitHub Actions to create releases with the workflow's requested
   `contents: write` permission.
5. Add the repository secrets listed below to the `release` environment.

In `Takhoffman/homebrew-tap`, create a `Casks` folder containing a short README
or placeholder. Protect its default branch after the first automated Cask
update succeeds.

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

That file is as sensitive as a password. Never add it to Git, unencrypted cloud
storage, a release, or an issue.

## Release secrets

The release workflow expects:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `SPARKLE_PRIVATE_KEY`
- `HOMEBREW_TAP_DEPLOY_KEY` (optional but recommended)

`SPARKLE_PRIVATE_KEY` is the exact exported key-file content, not an additional
base64 encoding of it. `HOMEBREW_TAP_DEPLOY_KEY` should be the private half of
a dedicated SSH key whose public half is installed as a write-enabled deploy
key on only `Takhoffman/homebrew-tap`. Do not reuse a personal SSH key.

Create that dedicated key with:

```sh
ssh-keygen -t ed25519 -N "" \
  -C "ssd-watcher-homebrew-tap" \
  -f /secure/temporary/location/ssd-watcher-homebrew-tap
```

Add the `.pub` file under the tap repository's **Settings → Deploy keys** with
write access, and store the private file as `HOMEBREW_TAP_DEPLOY_KEY` in the
source repository's `release` environment. After confirming the secret works,
remove the temporary files or keep one encrypted offline recovery copy.

Release secrets are used only after the public verification job passes and
must never be added to pull-request workflows.

## Standard release

1. Update `MARKETING_VERSION` in `project.yml`.
2. Move the relevant entries in `CHANGELOG.md` under the new version and date.
3. Add concise user-facing notes at `release-notes/<version>.md`.
4. Run `make check`.
5. Commit the release preparation and ensure `main` is green and clean.
6. Create and push an annotated tag:

   ```sh
   git tag -a v0.1.0 -m "SSD Watcher 0.1.0"
   git push origin v0.1.0
   ```

The tag starts two jobs. The first validates the tag, version, release notes,
generated project, and tests without access to secrets. The protected release
job then:

1. builds a universal Apple Silicon and Intel app;
2. Developer ID signs and Apple-notarizes the app and DMG;
3. verifies bundle versions and both architectures;
4. creates and EdDSA-signs the Sparkle ZIP and feed;
5. generates checksums and the Homebrew Cask;
6. publishes a GitHub release using the curated release notes; and
7. updates `Takhoffman/homebrew-tap` when its token is configured.

Afterward, verify installation on a Mac that has never built the project:

```sh
brew install --cask Takhoffman/tap/ssd-watcher
spctl --assess --type execute --verbose=2 \
  "/Applications/SSDWatcher.app"
```

Open the app, complete onboarding, run a manual discovery scan, check for
updates, then verify `brew upgrade --cask ssd-watcher` on the next release.

## Local recovery release

Add release notes and ensure the worktree is clean, then run:

```sh
NOTARYTOOL_PROFILE=SSDWatcherNotary scripts/release.sh 0.1.0
```

The script performs the same signing, notarization, architecture, Sparkle,
Cask, checksum, and Gatekeeper checks. Upload every file in `dist/` to a GitHub
release tagged `v<version>`. Copy `dist/Casks/ssd-watcher.rb` into
`Takhoffman/homebrew-tap/Casks/ssd-watcher.rb` if automated publishing is not
configured.

Users install and upgrade with:

```sh
brew install --cask Takhoffman/tap/ssd-watcher
brew upgrade --cask ssd-watcher
```
