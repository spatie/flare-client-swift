#if canImport(CrashReporter)
    import CrashReporter
    import Foundation

    @MainActor
    protocol CrashRecording {
        var hasPendingReport: Bool { get }
        func loadPendingReport() throws -> Data
        func purgePendingReport() throws
        func enable() throws
        func setCustomData(_ data: Data)
    }

    @MainActor
    final class NativeCrashRecorder: CrashRecording {
        private let reporter: PLCrashReporter

        init() {
            let configuration = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [])
            reporter = PLCrashReporter(configuration: configuration)
        }

        var hasPendingReport: Bool { reporter.hasPendingCrashReport() }

        func loadPendingReport() throws -> Data {
            try reporter.loadPendingCrashReportDataAndReturnError()
        }

        func purgePendingReport() throws {
            try reporter.purgePendingCrashReportAndReturnError()
        }

        func enable() throws {
            try reporter.enableAndReturnError()
        }

        func setCustomData(_ data: Data) {
            reporter.customData = data
        }
    }
#endif
