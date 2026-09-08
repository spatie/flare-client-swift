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
