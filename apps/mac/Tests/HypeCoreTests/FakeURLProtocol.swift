import Foundation

/// Intercepts `URLSession` requests in tests, so `Generator` can be exercised
/// end-to-end (request building, reply parsing, file writing) without a real
/// network call or API key — the Swift counterpart to the Qt app's Python
/// tests, which spin up a local `HTTPServer` as a fake endpoint.
final class FakeURLProtocol: URLProtocol {
    struct Recorded { let request: URLRequest; let bodyJSON: [String: Any] }
    nonisolated(unsafe) static var recorded: [Recorded] = []
    nonisolated(unsafe) static var responseStatus = 200
    nonisolated(unsafe) static var responseJSON: [String: Any] = [:]
    /// When true the request is recorded but never answered, like a slow model.
    nonisolated(unsafe) static var hang = false
    /// Replies to send in order (one per request); falls back to `responseJSON` when empty.
    nonisolated(unsafe) static var queuedJSON: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = request.httpBody ?? (request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 { data.append(buffer, count: read) }
            }
            return data
        }) ?? Data()
        let bodyJSON = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        FakeURLProtocol.recorded.append(.init(request: request, bodyJSON: bodyJSON))
        if FakeURLProtocol.hang { return }
        let reply = FakeURLProtocol.queuedJSON.isEmpty ? FakeURLProtocol.responseJSON : FakeURLProtocol.queuedJSON.removeFirst()
        let payload = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: FakeURLProtocol.responseStatus,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeURLProtocol.self]
        return URLSession(configuration: config)
    }
    static func reset(status: Int = 200, json: [String: Any]) {
        recorded = []
        responseStatus = status
        responseJSON = json
        hang = false
        queuedJSON = []
    }
}
