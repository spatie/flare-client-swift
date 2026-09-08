import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct HTTPResult: Sendable {
    var statusCode: Int
    var retryAfter: String?
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let validTimeout = timeout.isFinite && timeout > 0 ? timeout : 15
        configuration.timeoutIntervalForRequest = validTimeout
        configuration.timeoutIntervalForResource = validTimeout
        session = URLSession(configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FlareClientError.invalidResponse
        }
        return HTTPResult(
            statusCode: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    // A redirect must not forward the project key to another endpoint.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
