# Contributing

Thanks for helping make SSD Watcher safer and easier to use.

## Local setup

Install Xcode 16 or newer and XcodeGen, then run:

```sh
make test
make build
```

Open `SSDWatcher.xcodeproj` for normal Xcode development. `project.yml` is the
source of truth for project settings, so regenerate the project after changing
it.

To show the development preview window while running the otherwise menu-bar-only
app, set `SSD_WATCHER_SHOW_PREVIEW=1` in the scheme environment.

## Pull requests

- Keep monitoring read-only and local.
- Add deterministic tests for discovery or classification changes.
- Do not add telemetry, credentials, generated release artifacts, or private
  signing material.
- Preserve the rule that SSD Watcher never deletes data or terminates another
  application automatically.
- Explain any new filesystem locations or process inspection in the pull
  request's privacy impact section.

For security-sensitive reports, follow `SECURITY.md` instead of opening a public
issue.
