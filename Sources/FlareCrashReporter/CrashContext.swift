#if canImport(CrashReporter)
    import Flare
    import Foundation

    enum CrashContext {
        static let diagnosticsKey = "flare_client_swift.device_snapshot"

        static func encode(userContext: [String: FlareValue], device: [String: FlareValue]) throws -> Data {
            var context = userContext
            context[diagnosticsKey] = .object(device)
            let data = try JSONEncoder().encode(context)
            guard data.count <= 64 * 1024 else { throw FlareCrashReporterError.reportTooLarge }
            return data
        }
    }
#endif
