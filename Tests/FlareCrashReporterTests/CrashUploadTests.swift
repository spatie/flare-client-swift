#if canImport(CrashReporter)
    import Flare
    import Foundation
    import Testing
    @testable import FlareCrashReporter

    @MainActor
    final class FakeRecorder: CrashRecording {
        var pending: Data?
        var purged = false
        var enabled = false
        var customData = Data()
        var purgeFails = false
        var hasPendingReport: Bool { pending != nil }

        init(pending: Data? = nil) { self.pending = pending }
        func loadPendingReport() throws -> Data { try #require(pending) }
        func purgePendingReport() throws {
            if purgeFails { throw CocoaError(.fileWriteNoPermission) }
            purged = true
            pending = nil
        }
        func enable() { enabled = true }
        func setCustomData(_ data: Data) { customData = data }
    }

    actor UploadRecorder {
        var reports: [FlareReport] = []
        var failure: (any Error)?

        init(failure: (any Error)? = nil) { self.failure = failure }
        func setFailure(_ error: (any Error)?) { failure = error }
        func send(_ report: FlareReport) throws -> UUID? {
            reports.append(report)
            if let failure { throw failure }
            return report.id
        }
    }

    @MainActor
    struct CrashUploadTests {
        nonisolated private func convert(_ stored: StoredCrash) -> FlareReport {
            FlareReport(exceptionClass: "SIGABRT", message: "Native crash", handled: false, id: stored.id)
        }

        @Test func failedUploadStaysQueuedAndNextLaunchReusesItsID() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let recorder = FakeRecorder(pending: Data("native crash".utf8))
            let uploads = UploadRecorder(failure: URLError(.notConnectedToInternet))
            let first = try FlareCrashReporter(
                recorder: recorder, directory: directory, send: { try await uploads.send($0) }, convert: convert)
            let failed = await first.sendPendingReports()
            #expect(failed.sent == 0)
            #expect(failed.failures.count == 1)
            #expect(recorder.purged)
            #expect(try CrashStore(directory: directory, maximumReports: 20).pendingFiles().count == 1)

            await uploads.setFailure(nil)
            let relaunched = try FlareCrashReporter(
                recorder: FakeRecorder(), directory: directory, send: { try await uploads.send($0) }, convert: convert)
            let success = await relaunched.sendPendingReports()
            #expect(success.sent == 1)
            #expect(success.failures.isEmpty)
            #expect(try CrashStore(directory: directory, maximumReports: 20).pendingFiles().isEmpty)
            let attempts = await uploads.reports
            #expect(attempts.count == 2)
            #expect(attempts.first?.id == attempts.last?.id)
        }

        @Test func rejectionRetainsReportWithoutRetryingInSameLaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let uploads = UploadRecorder(failure: FlareClientError.rejected(statusCode: 429, retryAfter: "60"))
            let reporter = try FlareCrashReporter(
                recorder: FakeRecorder(pending: Data("crash".utf8)), directory: directory,
                send: { try await uploads.send($0) }, convert: convert)
            let result = await reporter.sendPendingReports()
            #expect(result.failures.count == 1)
            #expect(await uploads.reports.count == 1)
            #expect(try CrashStore(directory: directory, maximumReports: 20).pendingFiles().count == 1)
        }

        @Test func filteredReportIsDeliberatelyRemoved() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let reporter = try FlareCrashReporter(
                recorder: FakeRecorder(pending: Data("crash".utf8)), directory: directory, send: { _ in nil },
                convert: convert)
            let result = await reporter.sendPendingReports()
            #expect(result.filtered == 1)
            #expect(result.sent == 0)
            #expect(try CrashStore(directory: directory, maximumReports: 20).pendingFiles().isEmpty)
        }

        @Test func corruptFileDoesNotStopOtherReportsOrEscapeAsAnError() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CrashStore(directory: directory, maximumReports: 20)
            try store.archive(Data("valid".utf8))
            try Data("broken json".utf8).write(to: directory.appendingPathComponent("broken.json"))
            let reporter = try FlareCrashReporter(
                recorder: FakeRecorder(), directory: directory, send: { $0.id }, convert: convert)
            let result = await reporter.sendPendingReports()
            #expect(result.sent == 1)
            #expect(result.failures.count == 1)
            #expect(result.failures.first?.file == "broken.json")
        }

        @Test func diskFailureDoesNotPurgeTheOriginalNativeReport() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data("this is a file".utf8).write(to: directory)
            let recorder = FakeRecorder(pending: Data("crash".utf8))
            let reporter = try FlareCrashReporter(
                recorder: recorder, directory: directory, send: { $0.id }, convert: convert)
            let result = await reporter.sendPendingReports()
            #expect(result.failures.count == 1)
            #expect(!recorder.purged)
            #expect(recorder.pending != nil)
        }

        @Test func cancellationKeepsThePendingReport() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let reporter = try FlareCrashReporter(
                recorder: FakeRecorder(pending: Data("crash".utf8)), directory: directory,
                send: { _ in throw CancellationError() }, convert: convert)
            let result = await reporter.sendPendingReports()
            #expect(result.cancelled)
            #expect(result.failures.isEmpty)
            #expect(try CrashStore(directory: directory, maximumReports: 20).pendingFiles().count == 1)
        }

        @Test func secondUploadCannotSendTheSameReportConcurrently() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let gate = UploadGate()
            let reporter = try FlareCrashReporter(
                recorder: FakeRecorder(pending: Data("crash".utf8)), directory: directory,
                send: { report in
                    await gate.wait()
                    return report.id
                }, convert: convert)
            let first = Task { await reporter.sendPendingReports() }
            await gate.waitUntilEntered()
            let second = await reporter.sendPendingReports()
            #expect(second.failures.count == 1)
            await gate.release()
            #expect(await first.value.sent == 1)
        }

        @Test func nativeDecoderRejectsInvalidBytesAsAnError() throws {
            #expect(throws: (any Error).self) {
                try NativeCrashConverter.convert(StoredCrash(id: UUID(), data: Data("not a native report".utf8)))
            }
        }
    }

    actor UploadGate {
        private var entered = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var pending: CheckedContinuation<Void, Never>?

        func wait() async {
            entered = true
            for waiter in waiters { waiter.resume() }
            waiters = []
            await withCheckedContinuation { pending = $0 }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            pending?.resume()
            pending = nil
        }
    }
#endif
