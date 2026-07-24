# SSD Watcher

![SSD Watcher monitors several Codex database locations and protects an SSD from abnormal write activity](docs/images/ssd-watcher-hero.png)

SSD Watcher is a native macOS menu-bar utility that detects abnormal disk-write
activity before it quietly consumes storage endurance.

The first detector focuses on Codex feedback databases. It finds default,
custom, renamed, external-volume, and active `CODEX_HOME` locations using
database fingerprints, Codex markers, Spotlight, and runtime evidence rather
than relying on one folder name.

## What it does

- Discovers Codex homes automatically, including several homes on one Mac.
- Verifies SQLite schemas before monitoring a candidate.
- Samples insert counters and on-disk growth without reading log content.
- Shows live rates, storage totals, health, and short activity history.
- Sends a native notification when activity becomes abnormally high.
- Supports launch at login and secure in-app updates.

Normal Codex activity is usually far below SSD Watcher's default thresholds.
The defaults are intentionally conservative: 100 inserts/second is elevated
and 1,000 inserts/second is critical. A 1 MB/second database-growth rate is
also elevated, even when insert counters are unavailable.

## Install

The first public release will support either familiar Mac installation path:

1. Download the signed and notarized DMG from
   [GitHub Releases](https://github.com/Takhoffman/ssd-watcher/releases), drag
   SSD Watcher to Applications, and open it.
2. Install the Homebrew Cask:

   ```sh
   brew install --cask Takhoffman/tap/ssd-watcher
   ```

DMG installations update securely inside the app. Homebrew users can also run
`brew upgrade --cask ssd-watcher`.

## Product principles

- Useful immediately, without developer knowledge.
- Native, quiet, and visually clear.
- No accounts, advertising, or analytics.
- Never reads authentication data or log message contents.
- Never deletes files or terminates applications automatically.
- Open source under the MIT license.

## Development

Requirements:

- macOS 14 or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Generate the project and build:

```sh
make generate
make build
```

Build products use `/tmp/SSDWatcherDerivedData` because Xcode’s build database
cannot be hosted reliably on every external APFS volume.

Run tests:

```sh
make test
```

The generated `SSDWatcher.xcodeproj` is intentionally committed so the project
opens normally in Xcode. `project.yml` remains the source of truth.

## Detection and privacy

SSD Watcher uses a layered discovery strategy:

- known default locations and likely profile containers;
- Codex configuration, session, skill, and rule markers;
- open database files held by live Codex processes;
- Spotlight filename matches in the home folder and mounted local drives;
- a strict SQLite schema fingerprint; and
- folders added manually by the user.

It reads only paths, database schemas, SQLite sequence counters, file sizes, and
timestamps. It never reads prompt or response text, authentication files, or
credentials. It does not send analytics or anonymous system profiles. It never
deletes a database or terminates Codex automatically.

## Distribution

Public releases will use the same signed and notarized app bundle for:

- A DMG from GitHub Releases, with secure in-app updates powered by Sparkle.
- A Homebrew Cask for `brew install --cask ssd-watcher`.

Release signing and notarization are documented in `docs/RELEASING.md`.
