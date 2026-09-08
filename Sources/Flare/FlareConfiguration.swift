import Foundation

public struct FlareConfiguration: Sendable {
    public var apiKey: String
    public var applicationName: String
    public var applicationVersion: String?
    public var environment: String
    public var context: [String: FlareValue]
    public var timeout: TimeInterval

    public init(
        apiKey: String,
        applicationName: String,
        applicationVersion: String? = nil,
        environment: String = "production",
        context: [String: FlareValue] = [:],
        timeout: TimeInterval = 15
    ) {
        self.apiKey = apiKey
        self.applicationName = applicationName
        self.applicationVersion = applicationVersion
        self.environment = environment
        self.context = context
        self.timeout = timeout
    }
}
