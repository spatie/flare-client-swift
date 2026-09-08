#if canImport(CrashReporter)
    import Foundation
    import Testing
    @testable import FlareCrashReporter

    @MainActor
    struct CrashStoreTests {
        @Test func repeatedArchiveKeepsOneReportAndTheSameID() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CrashStore(directory: directory, maximumReports: 20)
            let data = Data("native crash".utf8)
            try store.archive(data)
            let first = try store.load(#require(store.pendingFiles().first))
            try store.archive(data)
            let files = try store.pendingFiles()
            #expect(files.count == 1)
            #expect(try store.load(#require(files.first)).id == first.id)
            #expect(first.data == data)
        }

        @Test func queueCapacityIsBounded() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = CrashStore(directory: directory, maximumReports: 2)
            for index in 0..<4 { try store.archive(Data("crash \(index)".utf8)) }
            #expect(try store.pendingFiles().count == 2)
        }
    }
#endif
