import Foundation

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func snapshot() -> Value {
        withValue { $0 }
    }
}

func makeMockedSession(
    responder: @escaping @Sendable (URLRequest) throws -> (Int, Data)
) -> URLSession {
    let sessionIdentifier = UUID().uuidString
    MockURLProtocol.register(responder: responder, for: sessionIdentifier)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.httpAdditionalHeaders = [MockURLProtocol.sessionIdentifierHeader: sessionIdentifier]
    return URLSession(configuration: configuration)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let sessionIdentifierHeader = "X-YCAIKit-Mock-Session"
    private static let responders = LockedBox<[String: @Sendable (URLRequest) throws -> (Int, Data)]>([:])

    static func register(
        responder: @escaping @Sendable (URLRequest) throws -> (Int, Data),
        for sessionIdentifier: String
    ) {
        responders.withValue { responders in
            responders[sessionIdentifier] = responder
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let sessionIdentifier = request.value(forHTTPHeaderField: Self.sessionIdentifierHeader) else {
            fatalError("MockURLProtocol missing session identifier.")
        }

        let responder = Self.responders.withValue { responders in
            responders[sessionIdentifier]
        }

        guard let responder else {
            fatalError("MockURLProtocol responder was not set for session \(sessionIdentifier).")
        }

        do {
            let (statusCode, data) = try responder(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
