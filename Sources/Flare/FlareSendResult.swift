import Foundation

public enum FlareSendResult: Sendable {
    /// The ingestion endpoint accepted the report. Processing happens asynchronously in Flare.
    case accepted(UUID)
    case filtered
    case cancelled
    case failed(any Error)
}
