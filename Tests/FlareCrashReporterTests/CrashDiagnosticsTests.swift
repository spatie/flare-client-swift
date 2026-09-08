#if canImport(CrashReporter)
    import Flare
    import Foundation
    import Testing
    @testable import FlareCrashReporter

    @MainActor
    struct CrashDiagnosticsTests {
        @Test func refreshPreservesUserContextAndReplacesMemorySnapshot() throws {
            let recorder = FakeRecorder()
            var device: [String: FlareValue] = ["memory_available_estimate_bytes": 100, "memory_sampled_at": "before"]
            let reporter = try FlareCrashReporter(
                recorder: recorder,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                send: { $0.id },
                convert: { .init(exceptionClass: "Test", message: "Test", id: $0.id) },
                diagnostics: { device }
            )
            try reporter.setContext(["screen": "workspace"])
            device = ["memory_available_estimate_bytes": 50, "memory_sampled_at": "after"]
            try reporter.refreshDiagnostics()
            let context = try JSONDecoder().decode([String: FlareValue].self, from: recorder.customData)
            #expect(context["screen"] == "workspace")
            #expect(context[CrashContext.diagnosticsKey] == .object(device))
        }

        @Test func invalidContextLeavesLastValidSnapshotIntact() throws {
            let recorder = FakeRecorder()
            let reporter = try FlareCrashReporter(
                recorder: recorder,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                send: { $0.id },
                convert: { .init(exceptionClass: "Test", message: "Test", id: $0.id) }
            )
            try reporter.setContext(["screen": "workspace"])
            let previous = recorder.customData
            #expect(throws: EncodingError.self) {
                try reporter.setContext(["invalid": .double(.infinity)])
            }
            #expect(recorder.customData == previous)
        }
    }
#endif
