import Foundation

public enum FlareClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidReport(String)
    case invalidResponse
    case rejected(statusCode: Int, retryAfter: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): "Invalid Flare configuration: \(reason)"
        case .invalidReport(let reason): "Invalid Flare report: \(reason)"
        case .invalidResponse: "Flare returned a non-HTTP response."
        case .rejected(let code, _): "Flare rejected the report with HTTP \(code)."
        }
    }
}
