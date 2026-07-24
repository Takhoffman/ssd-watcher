# Architecture

SSD Watcher is a small native SwiftUI menu-bar application with a deliberately
read-only monitoring pipeline.

```text
Local hints + lsof + Spotlight + manual folders
                         │
                         ▼
                Schema classification
                         │
                         ▼
          Read-only counters and file-set size
                         │
                         ▼
              Rate and health classification
                         │
                         ▼
             Menu-bar UI + local notification
```

## Discovery

`StorageDiscovery` generates candidate database paths from known defaults,
profile naming patterns, live processes, Spotlight, and manual selections.
`DatabaseProbe` then opens each candidate read-only and requires a
product-specific table-and-column fingerprint. Confirmed databases are grouped
into coherent Codex homes, OpenClaw state roots, or Hermes profiles.

Discovery runs at launch, when the user requests a scan, when a custom folder
changes, and automatically every five minutes. This slower cadence keeps new
profiles discoverable without repeatedly walking the filesystem.

## Sampling

Known locations are sampled every 10 seconds by default; the user can choose
5, 10, 30, or 60 seconds. A sample contains only:

- an append-oriented counter;
- the combined size of the SQLite database, `-wal`, and `-shm` files; and
- a timestamp.

The app calculates deltas between two samples and converts them to records per
second and bytes per second. Samples never overlap. When rediscovery changes a
location's database set, its baseline resets so an existing database is not
misreported as a sudden write spike.

Thirty-six rate points are retained in memory for each location. At the default
cadence, the graph therefore represents about six minutes. History is not
persisted.

## Health and notifications

Default health thresholds are:

| Level | Record rate | File growth |
| --- | ---: | ---: |
| Elevated | 100 records/s | 1 MiB/s |
| Critical | 1,000 records/s | 10 MiB/s |

Crossing into a higher warning level sends one native notification. Continuing
at the same level does not repeatedly notify. The record thresholds are
user-configurable; byte-growth thresholds are deliberately fixed as a
product-level safety backstop.

## Adding a detector

A detector should include:

1. An authoritative source link showing the storage path and override rules.
2. A schema fingerprint specific enough to reject unrelated databases.
3. A monotonic counter when one exists, with file growth as the universal
   fallback signal.
4. Discovery support for default, profile, runtime, Spotlight, and manual
   paths as appropriate.
5. Deterministic fixtures covering classification, sampling, grouping, and
   false positives.
6. An update to the privacy and supported-layout documentation.

Do not read content columns merely to improve identification or activity
measurement.
