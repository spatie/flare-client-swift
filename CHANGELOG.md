# Changelog

All notable changes to `flare-client-swift` will be documented in this file.

## 0.1.0 - 2026-09-08

- Add a Swift 6 reporting client with nonthrowing delivery results, context, breadcrumbs, supplied stack frames, and filtering.
- Add optional native crash capture through PLCrashReporter, a bounded local queue, and next-launch uploads.
- Preserve native binary UUIDs and addresses for separate symbolication.
- Add a standalone macOS example and tests for delivery, concurrency, cancellation, and crash recovery failures.

This release uses JavaScript compatibility metadata for Flare ingestion. Automatic source-level symbolication is not included.
