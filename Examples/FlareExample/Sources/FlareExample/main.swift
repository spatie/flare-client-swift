import Flare
import FlareCrashReporter
import Foundation

@main
struct FlareExample {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let mode = arguments.first, ["report", "crash", "upload"].contains(mode) else {
            print("Usage: FlareExample report | crash --confirm-crash | upload")
            return
        }

        let environment = ProcessInfo.processInfo.environment
        let key = environment["FLARE_API_KEY"] ?? ""
        guard mode == "crash" || !key.isEmpty else {
            print("Set FLARE_API_KEY to a Flare project public key.")
            exit(1)
        }
        let client = FlareClient(
            configuration: .init(
                apiKey: key,
                applicationName: "Flare Swift Example",
                applicationVersion: "0.1.0",
                environment: "testing"
            ))

        if mode == "report" {
            let report = FlareReport(
                exceptionClass: "FlareSwiftExample.DummyError",
                message: "Test report from the reusable Flare Swift package",
                stacktrace: [
                    .init(
                        file: "Demo/WorkspaceLoader.swift", lineNumber: 42, method: "openWorkspace(id:)",
                        className: "WorkspaceLoader",
                        codeSnippet: ["41": "// Synthetic example", "42": "throw DummyError.workspaceUnavailable"])
                ],
                context: ["synthetic": true, "purpose": "Verify the reusable Swift package"],
                breadcrumbs: [.init("Opened demo workspace")]
            )
            switch await client.report(report) {
            case .accepted(let id): print("Accepted report \(id)")
            case .filtered: print("Report filtered")
            case .cancelled:
                print("Report cancelled")
                exit(1)
            case .failed(let error):
                print("Report failed: \(error.localizedDescription)")
                exit(1)
            }
            return
        }

        do {
            let directory = environment["FLARE_CRASH_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            let crashReporter = try FlareCrashReporter(client: client, directory: directory)
            if mode == "crash" {
                guard arguments.contains("--confirm-crash") else {
                    print("Pass --confirm-crash to intentionally terminate this demo process.")
                    exit(1)
                }
                try crashReporter.start(context: ["synthetic": true, "purpose": "Native crash recovery smoke test"])
                abort()
            }

            let result = await crashReporter.sendPendingReports()
            print(
                "Sent: \(result.sent), filtered: \(result.filtered), failures: \(result.failures.count), cancelled: \(result.cancelled)"
            )
            for failure in result.failures { print(failure.reason) }
            if !result.failures.isEmpty || result.cancelled { exit(1) }
        } catch {
            print("Crash reporter setup failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
