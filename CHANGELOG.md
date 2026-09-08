# Changelog

All notable changes to `flare-client-swift` will be documented in this file.

## 1.0.0 - 2026-09-08

- Release the stable reporting and native crash capture API.

- Display device diagnostics in Flare's Application context alongside application identity and build information.
- Format memory amounts as readable KB, MB and GB values with two decimal places. Keep raw byte counts in local snapshots.

## 0.1.1 - 2026-09-08

- Include device model, total RAM and a timestamped estimate of available system memory in device context on Apple platforms.
- Refresh native crash diagnostics every 30 seconds while the app runs, preserving the last sample across a crash and restart.
- Keep older reports free of post-restart memory readings. Retain the previous snapshot if a refresh fails.

## 0.1.0 - 2026-09-08

- Add a Swift 6 reporting client with nonthrowing delivery results, context, breadcrumbs, supplied stack frames, and filtering.
- Add optional native crash capture through PLCrashReporter, a bounded local queue, and next-launch uploads.
- Preserve native binary UUIDs and addresses for separate symbolication.
- Add a standalone macOS example and tests for delivery, concurrency, cancellation, and crash recovery failures.

This release uses JavaScript compatibility metadata for Flare ingestion. Automatic source-level symbolication is not included.
