import Foundation
import os

final class URLProtocolMock: URLProtocol, @unchecked Sendable {
    typealias Responder = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    private static let lock = OSAllocatedUnfairLock<[String: Responder]>(initialState: [:])

    static func register(host: String, responder: @escaping Responder) {
        lock.withLock { $0[host] = responder }
    }

    static func unregister(host: String) {
        lock.withLock { _ = $0.removeValue(forKey: host) }
    }

    private static func responder(for host: String) -> Responder? {
        lock.withLock { $0[host] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return responder(for: host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host, let responder = Self.responder(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
