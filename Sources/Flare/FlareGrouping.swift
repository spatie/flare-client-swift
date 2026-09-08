/// Overrides the project's default grouping strategy for an individual report.
public enum FlareGrouping: String, Codable, Sendable {
    case exceptionClass = "exception_class"
    case exceptionMessage = "exception_message"
    case exceptionMessageAndClass = "exception_message_and_class"
    case fullStacktraceAndExceptionClassAndCode = "full_stacktrace_and_exception_class_and_code"
}
