#if canImport(CrashReporter)
    import CrashReporter
    import Flare
    import Foundation
    import Testing
    @testable import FlareCrashReporter

    struct NativeCrashConverterTests {
        @Test func convertsALiveNativeReportWithoutInstallingCrashHandlers() throws {
            let recorder = PLCrashReporter(configuration: .init(signalHandlerType: .mach, symbolicationStrategy: []))
            let data = try #require(recorder).generateLiveReportAndReturnError()
            let stored = StoredCrash(id: UUID(), data: data)
            let report = try NativeCrashConverter.convert(stored)
            #expect(report.id == stored.id)
            #expect(!report.handled)
            #expect(!report.stacktrace.isEmpty)
            #expect(report.code != nil)
            #expect(report.grouping == .fullStacktraceAndExceptionClassAndCode)
            #expect(report.context["native_crash"] != nil)
            #expect(report.attributes["os.version"] != nil)
            guard case .object(let device) = report.attributes["context.application"] else {
                Issue.record("Expected device context for a legacy native report")
                return
            }
            #expect(device["memory_available_estimate"] == nil)
            #expect(device["model"] != nil)
        }

        @Test func identifiesAnApplicationLaunchedThroughASymlink() {
            let image = "/project/.build/arm64-apple-macosx/debug/Demo"
            #expect(
                NativeCrashConverter.applicationImagePath(
                    imagePaths: ["/usr/lib/libSystem.dylib", image],
                    processPath: "/project/.build/debug/Demo",
                    processName: "Demo"
                ) == image)
        }

        @Test func conversionPreservesTheCapturedMemoryInsteadOfResamplingAfterRestart() throws {
            let recorder = try #require(
                PLCrashReporter(configuration: .init(signalHandlerType: .mach, symbolicationStrategy: [])))
            recorder.customData = try CrashContext.encode(
                userContext: ["screen": "workspace"],
                device: [
                    "memory_total_bytes": 1234, "memory_available_estimate_bytes": 456,
                    "memory_sampled_at": "before-crash",
                ]
            )
            let data = try recorder.generateLiveReportAndReturnError()
            let report = try NativeCrashConverter.convert(StoredCrash(id: UUID(), data: data))
            guard case .object(let device) = report.attributes["context.application"] else {
                Issue.record("Missing captured diagnostics")
                return
            }
            #expect(device["memory_total"] == "1.21 KB")
            #expect(device["memory_available_estimate"] == "456 B")
            #expect(device["memory_total_bytes"] == nil)
            #expect(device["memory_sampled_at"] == "before-crash")
            #expect(report.context["screen"] == "workspace")
            #expect(report.context[CrashContext.diagnosticsKey] == nil)
        }

        @Test func ambiguousBasenamesDoNotMisidentifyApplicationFrames() {
            let images = ["/first/Demo", "/second/Demo"]
            #expect(
                NativeCrashConverter.applicationImagePath(
                    imagePaths: images, processPath: "/unknown/Demo", processName: "Demo") == nil)
            #expect(
                NativeCrashConverter.applicationImagePath(
                    imagePaths: images, processPath: "/first/Demo", processName: "Demo") == "/first/Demo")
        }
    }
#endif
