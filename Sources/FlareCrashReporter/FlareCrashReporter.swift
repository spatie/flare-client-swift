#if canImport(CrashReporter)
    import Flare
    import Foundation

    /// Install once, early in app startup. Upload pending reports after the app launches.
    @MainActor
    public final class FlareCrashReporter {
        // PLCrashReporter's process-wide handlers must outlive the caller's local variable.
        private static var activeReporter: FlareCrashReporter?

        private let recorder: any CrashRecording
        private let store: CrashStore
        private let send: @Sendable (FlareReport) async throws -> UUID?
        private let convert: @Sendable (StoredCrash) throws -> FlareReport
        private var started = false
        private var uploading = false
        private var userContext: [String: FlareValue] = [:]
        private var diagnosticsTask: Task<Void, Never>?
        private let diagnostics: () -> [String: FlareValue]

        public convenience init(
            client: FlareClient,
            directory: URL? = nil,
            maximumPendingReports: Int = 20
        ) throws {
            let destination: URL
            if let directory {
                destination = directory
            } else {
                let base = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                )
                let identifier = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
                destination = base.appendingPathComponent(identifier).appendingPathComponent("Flare/CrashReports")
            }
            try self.init(
                recorder: NativeCrashRecorder(),
                directory: destination,
                maximumPendingReports: maximumPendingReports,
                send: { try await client.send($0) },
                convert: { try NativeCrashConverter.convert($0) }
            )
        }

        init(
            recorder: any CrashRecording,
            directory: URL,
            maximumPendingReports: Int = 20,
            send: @escaping @Sendable (FlareReport) async throws -> UUID?,
            convert: @escaping @Sendable (StoredCrash) throws -> FlareReport,
            diagnostics: @escaping () -> [String: FlareValue] = FlareDiagnostics.deviceContext
        ) throws {
            guard maximumPendingReports > 0, directory.isFileURL else {
                throw FlareCrashReporterError.invalidConfiguration
            }
            self.recorder = recorder
            store = CrashStore(directory: directory, maximumReports: maximumPendingReports)
            self.send = send
            self.convert = convert
            self.diagnostics = diagnostics
        }

        /// Saves the previous crash before enabling capture. Never installs a network crash callback.
        /// Call without an attached debugger, and do not combine with another crash handler.
        public func start(context: [String: FlareValue] = [:]) throws {
            guard !started else { return }
            guard Self.activeReporter == nil else { throw FlareCrashReporterError.alreadyStarted }
            try archivePendingReport()
            try setContext(context)
            try recorder.enable()
            started = true
            Self.activeReporter = self
            diagnosticsTask = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    } catch {
                        return
                    }
                    // Retain the last valid snapshot if a refresh cannot be encoded.
                    try? self?.refreshDiagnostics()
                }
            }
        }

        /// Replaces the context snapshot that PLCrashReporter will write if the process crashes.
        public func setContext(_ context: [String: FlareValue]) throws {
            let data = try CrashContext.encode(userContext: context, device: diagnostics())
            recorder.setCustomData(data)
            userContext = context
        }

        /// Refreshes the memory snapshot while the process is healthy. Never called by the crash handler.
        public func refreshDiagnostics() throws {
            try setContext(userContext)
        }

        /// Sends a snapshot of the local queue. Failed uploads remain for a later call or launch.
        /// Reports rejected by the client's beforeSend hook are deliberately removed.
        public func sendPendingReports() async -> FlareCrashUploadResult {
            guard !uploading else {
                return .init(failures: [
                    .init(file: nil, reason: FlareCrashReporterError.uploadInProgress.localizedDescription)
                ])
            }
            uploading = true
            defer { uploading = false }
            var result = FlareCrashUploadResult()
            do {
                try Task.checkCancellation()
                try archivePendingReport()
                for file in try store.pendingFiles() {
                    try Task.checkCancellation()
                    do {
                        let report = try await Task.detached(priority: .utility) { [convert, store] in
                            try convert(store.load(file))
                        }.value
                        try Task.checkCancellation()
                        let acceptedID = try await send(report)
                        try store.remove(file)
                        if acceptedID == nil {
                            result.filtered += 1
                        } else {
                            result.sent += 1
                        }
                    } catch {
                        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                            result.cancelled = true
                            return result
                        }
                        result.failures.append(.init(file: file.lastPathComponent, reason: error.localizedDescription))
                    }
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    result.cancelled = true
                } else {
                    result.failures.append(.init(file: nil, reason: error.localizedDescription))
                }
            }
            return result
        }

        private func archivePendingReport() throws {
            guard recorder.hasPendingReport else { return }
            try store.archive(recorder.loadPendingReport())
            try recorder.purgePendingReport()
        }
    }

    public struct FlareCrashUploadResult: Sendable {
        public internal(set) var sent = 0
        public internal(set) var filtered = 0
        public internal(set) var cancelled = false
        public internal(set) var failures: [Failure] = []

        public struct Failure: Sendable {
            public let file: String?
            public let reason: String
        }
    }

    public enum FlareCrashReporterError: Error, LocalizedError, Sendable {
        case invalidConfiguration
        case alreadyStarted
        case uploadInProgress
        case invalidNativeReport
        case reportTooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidConfiguration: "Crash reporting needs a file directory and a positive queue capacity."
            case .alreadyStarted: "A Flare crash reporter is already running in this process."
            case .uploadInProgress: "Pending crash reports are already being uploaded."
            case .invalidNativeReport: "The native crash report is missing required crash information."
            case .reportTooLarge: "The crash report or context exceeds the local size limit."
            }
        }
    }
#endif
