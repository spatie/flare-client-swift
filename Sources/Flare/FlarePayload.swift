import Foundation

struct FlarePayload: Encodable {
    var exceptionClass: String
    var message: String
    var code: String?
    var overriddenGrouping: FlareGrouping?
    var seenAtUnixNano: Int64
    var trackingUuid: String
    var handled: Bool
    var stacktrace: [FlareStackFrame]
    var openFrameIndex: Int?
    var attributes: [String: FlareValue]
    var events: [Event]

    init(report: FlareReport) throws {
        guard !report.exceptionClass.isEmpty, !report.message.isEmpty else {
            throw FlareClientError.invalidReport("An exception class and message are required.")
        }
        guard report.stacktrace.allSatisfy({ !$0.file.isEmpty && $0.lineNumber >= 0 }) else {
            throw FlareClientError.invalidReport(
                "Frames need a file and a nonnegative line number (zero means unknown).")
        }
        exceptionClass = report.exceptionClass
        message = report.message
        guard (report.code?.count ?? 0) <= 64 else {
            throw FlareClientError.invalidReport("The exception code cannot exceed 64 characters.")
        }
        code = report.code
        overriddenGrouping = report.grouping
        seenAtUnixNano = try Self.nanoseconds(report.occurredAt)
        trackingUuid = report.id.uuidString.lowercased()
        handled = report.handled
        stacktrace = report.stacktrace
        openFrameIndex = report.stacktrace.firstIndex(where: \.isApplicationFrame)
        attributes = report.attributes

        // Flare currently accepts this envelope as JavaScript. Swift-labeled reports
        // returned HTTP 201 but did not process during the initial integration test.
        attributes["telemetry.sdk.language"] = "javascript"
        attributes["telemetry.sdk.name"] = "flare-client-swift"
        attributes["telemetry.sdk.version"] = .string(FlareClient.version)
        attributes["flare.language.name"] = "javascript"
        attributes["flare.framework.name"] = "js"
        var context = report.context
        context["flare_client_swift"] = ["language": "Swift", "wire_language": "javascript"]
        attributes["context.custom"] = .object(context)
        events = try report.breadcrumbs.map {
            Event(
                startTimeUnixNano: try Self.nanoseconds($0.occurredAt),
                attributes: [
                    "glow.name": .string($0.message),
                    "glow.level": .string($0.level.rawValue),
                    "glow.context": .object($0.context),
                ]
            )
        }
    }

    static func nanoseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000_000_000
        guard value.isFinite, value >= 0, value < Double(Int64.max) else {
            throw FlareClientError.invalidReport("The timestamp cannot be represented in Unix nanoseconds.")
        }
        return Int64(value)
    }

    struct Event: Encodable {
        let type = "php_glow"
        var startTimeUnixNano: Int64
        let endTimeUnixNano: Int64? = nil
        var attributes: [String: FlareValue]

        enum CodingKeys: String, CodingKey {
            case type, startTimeUnixNano, endTimeUnixNano, attributes
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(startTimeUnixNano, forKey: .startTimeUnixNano)
            try container.encodeNil(forKey: .endTimeUnixNano)
            try container.encode(attributes, forKey: .attributes)
        }
    }
}
