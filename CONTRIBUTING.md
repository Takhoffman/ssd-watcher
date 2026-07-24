# Contributing

Thanks for helping make SSD Watcher safer and easier to use.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md). Questions and small
improvements are welcome; familiarity with every part of the app is not
expected.

## Local setup

Install Xcode 16 or newer and XcodeGen, then run:

```sh
make check
```

Open `SSDWatcher.xcodeproj` for normal Xcode development. `project.yml` is the
source of truth for project settings, so regenerate the project after changing
it.

To show the development preview window while running the otherwise menu-bar-only
app, set `SSD_WATCHER_SHOW_PREVIEW=1` in the scheme environment.

The [architecture guide](docs/ARCHITECTURE.md) explains discovery, sampling,
health classification, and the requirements for a new storage detector.

## Pull requests

- Keep monitoring read-only and local.
- Add deterministic tests for discovery or classification changes.
- Do not add telemetry, credentials, generated release artifacts, or private
  signing material.
- Preserve the rule that SSD Watcher never deletes data or terminates another
  application automatically.
- Explain any new filesystem locations or process inspection in the pull
  request's privacy impact section.
- Keep changes focused enough to review and explain the user-visible outcome.
- Run `make check` before opening the pull request.

For security-sensitive reports, follow `SECURITY.md` instead of opening a public
issue.

By submitting a contribution, you agree that it may be distributed under the
repository's [MIT license](LICENSE).
