# Privacy

SSD Watcher is designed to answer one narrow question: are supported agent
databases writing at an unusual rate? It does that locally and does not collect
analytics.

## Data SSD Watcher reads

For recognized Codex, OpenClaw, and Hermes SQLite databases, SSD Watcher reads:

- the database path and filename;
- table and column names needed to verify the database type;
- monotonic SQLite sequence values or aggregate row counts;
- database, WAL, and shared-memory file sizes; and
- filesystem timestamps and available disk capacity.

SQLite connections are opened read-only. SSD Watcher never executes an insert,
update, delete, migration, checkpoint, vacuum, or repair operation.

## Discovery

Discovery uses several local signals:

- known default homes and likely profile containers;
- user-selected folders;
- `lsof` output for database files already open by likely agent processes; and
- Spotlight filename results in the user's home and mounted local volumes.

Every candidate must pass a strict schema fingerprint before it is monitored.
A matching folder or filename alone is insufficient.

## Data SSD Watcher does not read

SSD Watcher does not read:

- prompt, response, transcript, memory, or message text;
- API keys, tokens, cookies, or credentials;
- agent configuration values;
- browser history; or
- unrelated SQLite databases.

The app does not upload database metadata, paths, device identifiers, usage
statistics, or crash telemetry.

## Network access

The monitoring and discovery engine makes no network requests. Sparkle checks
the project's GitHub-hosted update feed over HTTPS. Sparkle system profiling is
explicitly disabled, so the update request does not include an anonymous
hardware or operating-system profile. As with any HTTPS request, GitHub can see
ordinary connection metadata such as an IP address and user agent.

## Data stored by SSD Watcher

Preferences such as onboarding state, scan interval, thresholds, notification
choice, and manually selected paths are stored in the app's standard macOS
preferences domain. The short activity graph is held in memory and resets when
the app quits.

SSD Watcher never deletes agent data, changes agent configuration, or
terminates another application automatically.

## Reporting a privacy problem

Treat unexpected content access, data modification, or network transmission as
a security issue. Report it privately using [SECURITY.md](../SECURITY.md).
