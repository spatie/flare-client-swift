import Foundation

public struct FlareReport: Codable, Sendable, Equatable {
    public var id: UUID
    public var occurredAt: Date
    public var exceptionClass: String
    public var message: String
    public var code: String?
    public var grouping: FlareGrouping?
    public var handled: Bool
    public var stacktrace: [FlareStackFrame]
    public var context: [String: FlareValue]
    public var attributes: [String: FlareValue]
    public var breadcrumbs: [FlareBreadcrumb]

    public init(
        exceptionClass: String,
        message: String,
        code: String? = nil,
        grouping: FlareGrouping? = nil,
        handled: Bool = true,
        stacktrace: [FlareStackFrame] = [],
        context: [String: FlareValue] = [:],
        attributes: [String: FlareValue] = [:],
        breadcrumbs: [FlareBreadcrumb] = [],
        occurredAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.exceptionClass = exceptionClass
        self.message = message
        self.code = code
        self.grouping = grouping
        self.handled = handled
        self.stacktrace = stacktrace
        self.context = context
        self.attributes = attributes
        self.breadcrumbs = breadcrumbs
    }

    /// Swift errors do not retain their throw-site stack. This records the reporting location.
    public init(
        error: any Error,
        context: [String: FlareValue] = [:],
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        self.init(
            exceptionClass: String(reflecting: type(of: error)),
            message: (error as? any LocalizedError)?.errorDescription ?? String(describing: error),
            stacktrace: [.init(file: file, lineNumber: line, method: function)],
            context: context
        )
    }
}

/// An explicit timeline entry. The client never records app activity automatically.
public struct FlareBreadcrumb: Codable, Sendable, Equatable {
    public var message: String
    public var level: Level
    public var context: [String: FlareValue]
    public var occurredAt: Date

    public enum Level: String, Codable, Sendable {
        case debug, info, warning, error
    }

    public init(
        _ message: String,
        level: Level = .info,
        context: [String: FlareValue] = [:],
        occurredAt: Date = Date()
    ) {
        self.message = message
        self.level = level
        self.context = context
        self.occurredAt = occurredAt
    }
}
