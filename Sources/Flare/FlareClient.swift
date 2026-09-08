import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A reusable, concurrency-safe client. Each send makes a single HTTP request.
public struct FlareClient: Sendable {
    public static let version = "0.1.2"

    private let configuration: FlareConfiguration
    private let transport: any HTTPTransport
    private let beforeSend: @Sendable (FlareReport) -> FlareReport?

    public init(
        configuration: FlareConfiguration,
        beforeSend: @escaping @Sendable (FlareReport) -> FlareReport? = { $0 }
    ) {
        self.init(
            configuration: configuration, transport: URLSessionTransport(timeout: configuration.timeout),
            beforeSend: beforeSend)
    }

    init(
        configuration: FlareConfiguration,
        transport: any HTTPTransport,
        beforeSend: @escaping @Sendable (FlareReport) -> FlareReport? = { $0 }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.beforeSend = beforeSend
    }

    /// Returns the report ID on HTTP 201, or nil when filtered by beforeSend.
    /// Acceptance by ingestion does not guarantee that Flare has processed the report.
    @discardableResult
    public func send(_ report: FlareReport) async throws -> UUID? {
        try Task.checkCancellation()
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !configuration.apiKey.contains(where: { $0.isNewline })
        else {
            throw FlareClientError.invalidConfiguration("A project API key is required.")
        }
        guard configuration.timeout.isFinite, configuration.timeout > 0 else {
            throw FlareClientError.invalidConfiguration("The timeout must be a positive, finite number.")
        }

        var prepared = report
        prepared.context = configuration.context.merging(report.context) { _, new in new }
        prepared.attributes = defaultAttributes.merging(report.attributes) { _, new in new }
        guard let filtered = beforeSend(prepared) else { return nil }

        let payload = try FlarePayload(report: filtered)
        var request = URLRequest(url: URL(string: "https://ingress.flareapp.io/v1/errors")!)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("flare-client-swift/\(Self.version)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)
        guard (request.httpBody?.count ?? 0) <= 2 * 1024 * 1024 else {
            throw FlareClientError.invalidReport("The encoded report exceeds 2 MiB.")
        }

        try Task.checkCancellation()
        let response = try await transport.send(request)
        guard response.statusCode == 201 else {
            throw FlareClientError.rejected(statusCode: response.statusCode, retryAfter: response.retryAfter)
        }
        return filtered.id
    }

    /// Reports a caught error without throwing, with the call site as its single frame.
    @discardableResult
    public func report(
        _ error: any Error,
        context: [String: FlareValue] = [:],
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) async -> FlareSendResult {
        await report(FlareReport(error: error, context: context, file: file, line: line, function: function))
    }

    /// Best-effort delivery suitable for app error paths. Failures never escape as thrown errors.
    @discardableResult
    public func report(_ report: FlareReport) async -> FlareSendResult {
        do {
            guard let id = try await send(report) else { return .filtered }
            return .accepted(id)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return .cancelled
            }
            return .failed(error)
        }
    }

    private var defaultAttributes: [String: FlareValue] {
        var attributes: [String: FlareValue] = [
            "context.application": .object(FlareDiagnostics.applicationContext(from: FlareDiagnostics.deviceContext())),
            "service.name": .string(configuration.applicationName),
            "service.stage": .string(configuration.environment),
            "flare.entry_point.type": "cli",
            "flare.entry_point.value": .string(configuration.applicationName),
        ]
        if let version = configuration.applicationVersion {
            attributes["service.version"] = .string(version)
        }
        return attributes
    }
}
