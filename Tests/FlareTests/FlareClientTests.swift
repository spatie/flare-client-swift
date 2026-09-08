import Foundation
import Testing

@testable import Flare

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

actor RecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let response: HTTPResult
    let failure: URLError?

    init(status: Int = 201, retryAfter: String? = nil, failure: URLError? = nil) {
        response = HTTPResult(statusCode: status, retryAfter: retryAfter)
        self.failure = failure
    }

    func send(_ request: URLRequest) throws -> HTTPResult {
        requests.append(request)
        if let failure { throw failure }
        return response
    }
}

struct FlareClientTests {
    let configuration = FlareConfiguration(
        apiKey: "test-key", applicationName: "Example", applicationVersion: "1.2.3", environment: "testing")

    @Test func sendsDocumentedPayloadWithSwiftFramesAndCompatibilityMetadata() async throws {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport)
        let report = FlareReport(
            exceptionClass: "ExampleError",
            message: "Test error",
            stacktrace: [
                .init(
                    file: "App/Loader.swift", lineNumber: 42, method: "load()", className: "Loader",
                    codeSnippet: ["42": "throw ExampleError.failed"])
            ],
            context: ["attempt": 2, "nested": ["enabled": true]],
            breadcrumbs: [.init("Opened workspace", occurredAt: Date(timeIntervalSince1970: 1_700_000_000))],
            occurredAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        #expect(try await client.send(report) == report.id)
        let requests = await transport.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.url?.absoluteString == "https://ingress.flareapp.io/v1/errors")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-token") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let data = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["seenAtUnixNano"] as? Int64 == 1_700_000_001_000_000_000)
        #expect(payload["trackingUuid"] as? String == report.id.uuidString.lowercased())
        let attributes = try #require(payload["attributes"] as? [String: Any])
        #expect(attributes["flare.language.name"] as? String == "javascript")
        #expect(attributes["service.version"] as? String == "1.2.3")
        #expect(attributes["service.stage"] as? String == "testing")
        let frames = try #require(payload["stacktrace"] as? [[String: Any]])
        #expect(frames.first?["class"] as? String == "Loader")
        #expect(frames.first?["codeSnippet"] as? [String: String] == ["42": "throw ExampleError.failed"])
        let events = try #require(payload["events"] as? [[String: Any]])
        #expect(events.first?["type"] as? String == "php_glow")
        #expect(events.first?["endTimeUnixNano"] is NSNull)
        #expect(!String(decoding: data, as: UTF8.self).contains("test-key"))
    }

    @Test func redactionSeesMergedContextAndCanRemoveFrames() async throws {
        var configuration = configuration
        configuration.context = ["secret": "remove-me", "account": "default"]
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport) { report in
            var report = report
            report.context.removeValue(forKey: "secret")
            report.stacktrace = []
            return report
        }
        try await client.send(.init(exceptionClass: "Test", message: "Test", context: ["account": "override"]))
        let request = try #require(await transport.requests.first)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("remove-me"))
        #expect(body.contains("override"))
        #expect(!body.contains("default"))
    }

    @Test func filteredReportsDoNotUseNetwork() async throws {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport, beforeSend: { _ in nil })
        #expect(try await client.send(.init(exceptionClass: "Test", message: "Test")) == nil)
        #expect(await transport.requests.isEmpty)
    }

    @Test func publicReportingReturnsFailuresInsteadOfThrowing() async {
        let transport = RecordingTransport(status: 500)
        let client = FlareClient(configuration: configuration, transport: transport)
        let result = await client.report(FlareReport(exceptionClass: "Test", message: "Test"))
        guard case .failed(let error) = result else {
            Issue.record("Expected a returned failure")
            return
        }
        #expect(error as? FlareClientError == .rejected(statusCode: 500, retryAfter: nil))
        #expect(await transport.requests.count == 1)
    }

    @Test func publicReportingReturnsCancellationAndDoesNotSend() async {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await client.report(FlareReport(exceptionClass: "Test", message: "Test"))
        }
        guard case .cancelled = await task.value else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func publicClientHandlesInvalidTimeoutWithoutCrashing() async {
        var invalid = configuration
        invalid.timeout = .nan
        let client = FlareClient(configuration: invalid)
        guard case .failed(let error) = await client.report(FlareReport(exceptionClass: "Test", message: "Test")) else {
            Issue.record("Expected invalid configuration result")
            return
        }
        #expect(error is FlareClientError)
    }

    @Test func oversizedPayloadDoesNotUseNetwork() async {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport)
        let result = await client.report(
            FlareReport(exceptionClass: "Test", message: String(repeating: "x", count: 2 * 1024 * 1024)))
        guard case .failed = result else {
            Issue.record("Expected size limit failure")
            return
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [200, 301, 401, 403, 422, 429, 500])
    func nonCreatedResponsesAreFailuresWithoutAutomaticRetry(status: Int) async throws {
        let transport = RecordingTransport(status: status, retryAfter: "60")
        let client = FlareClient(configuration: configuration, transport: transport)
        await #expect(throws: FlareClientError.rejected(statusCode: status, retryAfter: "60")) {
            try await client.send(.init(exceptionClass: "Test", message: "Test"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func networkFailuresPropagate() async {
        let transport = RecordingTransport(failure: URLError(.notConnectedToInternet))
        let client = FlareClient(configuration: configuration, transport: transport)
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await client.send(.init(exceptionClass: "Test", message: "Test"))
        }
    }

    @Test func rejectsInvalidTimestampsWithoutTrappingOrSending() async {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport)
        for interval in [-1.0, Double.infinity, Double.nan, Double(Int64.max)] {
            await #expect(throws: FlareClientError.self) {
                try await client.send(
                    .init(exceptionClass: "Test", message: "Test", occurredAt: Date(timeIntervalSince1970: interval)))
            }
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func invalidConfigurationAndNonFiniteContextDoNotUseNetwork() async {
        let transport = RecordingTransport()
        var invalid = configuration
        invalid.apiKey = "\n"
        let client = FlareClient(configuration: invalid, transport: transport)
        await #expect(throws: FlareClientError.self) {
            try await client.send(.init(exceptionClass: "Test", message: "Test"))
        }
        let valid = FlareClient(configuration: configuration, transport: transport)
        await #expect(throws: EncodingError.self) {
            try await valid.send(
                .init(exceptionClass: "Test", message: "Test", context: ["invalid": .double(.infinity)]))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func errorConvenienceUsesLocalizedMessageAndCallerLocation() {
        struct DemoError: LocalizedError { var errorDescription: String? { "Workspace unavailable" } }
        let report = FlareReport(error: DemoError(), file: "Demo/App.swift", line: 123, function: "open()")
        #expect(report.message == "Workspace unavailable")
        #expect(report.exceptionClass.contains("DemoError"))
        #expect(report.stacktrace == [.init(file: "Demo/App.swift", lineNumber: 123, method: "open()")])
        #expect(report.handled)
    }

    @Test func reportRoundTripPreservesNestedValuesAndIdentity() throws {
        let report = FlareReport(
            exceptionClass: "Test", message: "Test", context: ["nested": ["array": [1, true, nil, 1.5, "text"]]])
        #expect(try JSONDecoder().decode(FlareReport.self, from: JSONEncoder().encode(report)) == report)
    }

    @Test func concurrentReportsHaveIndependentBodies() async throws {
        let transport = RecordingTransport()
        let client = FlareClient(configuration: configuration, transport: transport)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try await client.send(.init(exceptionClass: "Test", message: "Report \(index)"))
                }
            }
            try await group.waitForAll()
        }
        let bodies = await transport.requests.compactMap(\.httpBody)
        let ids = try bodies.map { try JSONDecoder().decode([String: FlareValue].self, from: $0)["trackingUuid"] }
        #expect(bodies.count == 20)
        #expect(Set(ids.map { String(describing: $0) }).count == 20)
    }
}
