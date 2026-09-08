#if canImport(CrashReporter)
    import CryptoKit
    import Foundation

    struct StoredCrash: Codable, Sendable {
        var id: UUID
        var data: Data
    }

    @MainActor
    struct CrashStore {
        let directory: URL
        let maximumReports: Int

        func archive(_ data: Data) throws {
            guard data.count <= 8 * 1024 * 1024 else { throw FlareCrashReporterError.reportTooLarge }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // A failed purge can expose the same native report again on the next launch.
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let destination = directory.appendingPathComponent(digest).appendingPathExtension("json")
            guard !FileManager.default.fileExists(atPath: destination.path) else { return }

            let record = StoredCrash(id: UUID(), data: data)
            try JSONEncoder().encode(record).write(to: destination, options: .atomic)
            let files = try pendingFiles()
            for file in files.prefix(max(0, files.count - maximumReports)) {
                try FileManager.default.removeItem(at: file)
            }
        }

        func pendingFiles() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return left == right ? $0.lastPathComponent < $1.lastPathComponent : left < right
            }
        }

        nonisolated func load(_ file: URL) throws -> StoredCrash {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 12 * 1024 * 1024 else { throw FlareCrashReporterError.reportTooLarge }
            return try JSONDecoder().decode(StoredCrash.self, from: Data(contentsOf: file))
        }

        func remove(_ file: URL) throws {
            try FileManager.default.removeItem(at: file)
        }
    }
#endif
