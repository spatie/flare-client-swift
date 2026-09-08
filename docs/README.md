# Send Swift errors and native crash reports to Flare

[![Tests](https://github.com/spatie/flare-client-swift/actions/workflows/tests.yml/badge.svg)](https://github.com/spatie/flare-client-swift/actions/workflows/tests.yml)

Report Swift errors to [Flare](https://flareapp.io), with structured context, breadcrumbs, and stack frames. The optional `FlareCrashReporter` product captures native crashes using [PLCrashReporter](https://github.com/microsoft/plcrashreporter), saves them locally, and uploads them after the app launches again.

```swift
import Flare

let flare = FlareClient(configuration: .init(
    apiKey: "YOUR_PROJECT_PUBLIC_KEY",
    applicationName: "My App",
    applicationVersion: "1.0.0"
))

do {
    try openWorkspace()
} catch {
    await flare.report(error, context: ["action": "open_workspace"])
}
```

`report` does not throw. Network failures, rejected requests, and encoding errors become a `FlareSendResult.failed` value. Reporting never deliberately terminates the app or retries in a tight loop.

## Requirements

- Swift 6.0 or newer.
- macOS 12+, iOS 15+, or tvOS 15+.
- The `Flare` reporting client also supports Linux. Native crash capture supports the Apple platforms listed above.
- A Flare project and its public project API key.

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/spatie/flare-client-swift.git", from: "0.1.0"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "Flare", package: "flare-client-swift"),
            .product(name: "FlareCrashReporter", package: "flare-client-swift"),
        ]
    ),
]
```

Omit the `FlareCrashReporter` product dependency if you only need error reporting. The core client uses Foundation and does not link PLCrashReporter. Swift Package Manager still resolves the package's declared dependencies.

In Xcode, add `https://github.com/spatie/flare-client-swift.git` under **File > Add Package Dependencies**, then select the products your app needs.

## Native crash capture

Configure one reporter early in app startup. Uploads should run in a task so launching your interface does not wait for the network:

```swift
import Flare
import FlareCrashReporter

@MainActor
func configureCrashReporting(client: FlareClient) {
    do {
        let crashes = try FlareCrashReporter(client: client)
        try crashes.start(context: ["release_channel": "stable"])

        Task {
            let result = await crashes.sendPendingReports()
            // Optional: inspect result.failures in your local diagnostics.
            // Upload failure does not throw or prevent the app from starting.
            _ = result
        }
    } catch {
        // Continue normal app startup if capture cannot be configured.
        print("Could not enable crash capture: \(error.localizedDescription)")
    }
}
```

The reporter retains itself after a successful `start()`. Calling `start()` again on the same instance is harmless. A second reporter cannot install another set of handlers. Keep your own reference if you want to call `setContext` or retry an upload later.

1. PLCrashReporter writes a native report when the process crashes. No Swift task or network request starts in the crash handler.
2. On the next launch, `start()` copies the previous report into the durable queue before clearing PLCrashReporter's copy and enabling capture again.
3. `sendPendingReports()` decodes reports off the main actor and sends them asynchronously. Successful uploads are removed. Reports filtered by `beforeSend` are also removed deliberately.
4. Network, HTTP, file, and decoding failures are returned in `result.failures`. Failed reports stay queued. A malformed file does not stop other reports. Cancellation retains unsent reports, and overlapping upload calls do not send the same queue twice through one reporter.

Only run uploads once per launch, or retry later after connectivity changes. Each call attempts each queued report at most once. The default request timeout is 15 seconds. The queue retains up to 20 reports and evicts the oldest when full. Raw reports are limited to 8 MiB, crash context to 64 KiB, and encoded HTTP payloads to 2 MiB. Oversized or permanently rejected reports may need removal from the local queue, or will eventually be evicted.

The default queue is under Application Support, namespaced by your app's bundle identifier (or process name for a command-line tool). You can pass `directory:` and `maximumPendingReports:` when constructing the crash reporter. Use one reporter and queue per process; multiple processes must use separate queues. Raw native files stay on the device and can contain local paths. The upload contains binary basenames, image UUIDs, addresses, and thread frames, rather than the raw native file.

Install native capture without an attached debugger and do not combine it with another crash-reporting SDK's handlers. Typical signals, Mach exceptions, and uncaught Objective-C exceptions are captured. Force quit, `SIGKILL`, and every OS termination condition cannot be captured. If the user never opens the app again, the queued crash is not uploaded.

### Symbols and source lines

Native reports contain the crashed thread's frames, other threads, binary UUIDs, load addresses, image offsets, the crash timestamp, and the crashed application's version. The initial native capture uses no in-process symbolication. Frames therefore generally show a binary name and offset, with line `0` meaning unknown. Exception messages may provide additional detail.

Keep the matching binary and dSYM for every release. Source-level symbolication is a separate step; this package does not upload dSYMs or provide a symbol server. Once you have symbolicated a report, you can send its source frames through `FlareReport`. Binary UUIDs and addresses are in the `native_crash` custom context for this purpose.

Native crashes override the default grouping with the full stack trace, exception class, and application binary UUID. Binary-relative offsets stay stable across address randomization. Different stack locations and different builds stay distinguishable even when source line numbers are unavailable. You can also set `grouping` and `code` on a manually created `FlareReport`.

### Updating crash context

```swift
try crashes.setContext([
    "screen": "workspace",
    "action": "open_terminal",
])
```

This replaces the snapshot captured with a future crash. Ordinary client context is applied when a report is uploaded, so use `setContext` for state that must reflect the time of the crash. Source code, user identity, files, and app activity are not collected automatically by the core client. Avoid adding credentials or private content to context or error messages.

## Reporting errors and supplied frames

Swift `Error` values do not retain their throw-site stack. `flare.report(error)` records the reporting call site using `#fileID`, `#line`, and `#function`. That frame is a location hint, not a captured crash stack. `LocalizedError.errorDescription` is used when available.

For your own symbolicated stack, pass explicit frames:

```swift
let report = FlareReport(
    exceptionClass: "WorkspaceError",
    message: "The workspace could not be opened",
    stacktrace: [
        FlareStackFrame(
            file: "MyApp/WorkspaceLoader.swift",
            lineNumber: 42,
            method: "openWorkspace(id:)",
            className: "WorkspaceLoader",
            codeSnippet: ["42": "throw WorkspaceError.unavailable"]
        ),
    ],
    context: ["attempt": 2],
    breadcrumbs: [FlareBreadcrumb("Selected workspace")]
)

let result = await flare.report(report)
```

`FlareValue` supports strings, booleans, integers, doubles, arrays, objects, and null, with Swift literal syntax. Reports and their values are `Codable` and `Sendable`. Reuse the client across tasks. The core client does not persist ordinary errors automatically.

`FlareSendResult` is `.accepted(UUID)`, `.filtered`, `.cancelled`, or `.failed(Error)`. For code that needs throwing delivery, `try await flare.send(report)` returns the report UUID, or `nil` if filtered. HTTP 201 means the ingestion endpoint accepted the request; processing happens later in Flare. Retry requests can produce duplicate occurrences if the original response was lost; a stable tracking UUID is sent, but backend deduplication is not guaranteed.

## Configuration and filtering

```swift
let flare = FlareClient(
    configuration: .init(
        apiKey: "YOUR_PROJECT_PUBLIC_KEY",
        applicationName: "My App",
        applicationVersion: "1.0.0",
        environment: "production",
        context: ["release_channel": "stable"],
        timeout: 15
    ),
    beforeSend: { report in
        var report = report
        report.context.removeValue(forKey: "private_note")
        return report
    }
)
```

`beforeSend` sees the merged app and report context and attributes. Return `nil` to drop the report. The closure must be `Sendable` and may run concurrently. It should be a small, safe transformation; it is application code, so the SDK cannot recover from a fatal error inside that closure.

Enable capture and call the client only in the environments where you want telemetry. For sandboxed Apple apps, enable outgoing network connections. Use a project public key in distributed apps, not a personal access token. Keys are sent only in the HTTP header, and redirects are refused. The client does not log request bodies or credentials.

## Flare compatibility

This first release sends the [documented Flare error protocol](https://flareapp.io/docs/protocol/errors/payload). Flare currently processes the payload using JavaScript language metadata, while the custom context identifies the actual client as Swift. In the initial integration test, a Swift-labeled report received HTTP 201 but did not appear; the JavaScript-compatible envelope did.

Create a JavaScript project in Flare for now. Reports display a JavaScript language label, but preserve Swift exception names, frames, source snippets, and context. There is no npm, Vite, or JavaScript runtime dependency. The default entry point is `cli`, displayed as Command, because Flare's protocol does not currently document a native-app entry point. You can supply documented entry-point attributes in `FlareReport.attributes`.

## Example and tests

```shell
swift test
swift build --configuration release
```

The [standalone macOS example](../Examples/FlareExample) can send a synthetic report or exercise a real crash in its own process:

```shell
export FLARE_API_KEY='YOUR_PROJECT_PUBLIC_KEY'
swift run --package-path Examples/FlareExample FlareExample report
swift run --package-path Examples/FlareExample FlareExample crash --confirm-crash
swift run --package-path Examples/FlareExample FlareExample upload
```

The crash command intentionally exits with `SIGABRT`. Run it separately, without a debugger. The next command recovers and uploads that crash. Set `FLARE_CRASH_DIRECTORY` if you want a dedicated queue directory. The example is not part of the library's products.

## Credits

- [Spatie](https://spatie.be)
- [PLCrashReporter contributors](https://github.com/microsoft/plcrashreporter)

## License

The MIT License. See [LICENSE.md](../LICENSE.md).
