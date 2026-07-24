# Changelog

Notable user-facing changes are recorded here. SSD Watcher follows
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.1 - 2026-07-24

### Fixed

- Keep the menu-bar dashboard at a usable height instead of allowing its
  scrollable content to collapse behind the footer.

## 0.1.0 - 2026-07-24

### Added

- Native macOS menu-bar monitoring for Codex, OpenClaw, and Hermes SQLite
  stores.
- Schema-verified discovery across default homes, named profiles, custom
  folders, live processes, Spotlight results, and mounted local drives.
- Continuous record-rate and file-growth sampling with native notifications.
- Automatic five-minute rediscovery for stores created while the app is
  running.
- Signed Sparkle updates, notarized DMG packaging, and Homebrew Cask support.

### Privacy

- Monitoring is read-only and local.
- Telemetry and Sparkle system profiling are disabled.
