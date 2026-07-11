import Domain
import Foundation

/// Raw-HTML contract for uta-net.com, which publishes no JSON API: the data
/// source scrapes the song-title search results and each song's lyrics page.
/// Papyrus is deliberately not used here — it is a JSON-API abstraction, and
/// uta-net's capitalized query keys (`Keyword`, `Aselect`, `Bselect`) cannot be
/// derived from Swift parameter names.
public protocol UtaNet: Sendable {
    func searchSongs(keyword: String) async throws -> String
    func lyricsPage(songID: Int) async throws -> String
}

public struct UtaNetAPI: Sendable {
    /// Browser-like User-Agent: uta-net sits behind Cloudflare bot protection.
    /// URLSession's TLS fingerprint passes the check (curl's does not), but the
    /// request must also carry a plausible browser UA to reach the real page.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private let baseURL: String
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init() {
        self.init(baseURL: Self.baseURL) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(
        baseURL: String,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.baseURL = baseURL
        self.fetch = fetch
    }
}

extension UtaNetAPI: UtaNet {
    public func searchSongs(keyword: String) async throws -> String {
        guard var components = URLComponents(string: baseURL) else { throw UtaNetError.invalidURL }
        components.path = "/search/"
        // Aselect=2 = search by song title. Bselect=3 mirrors the value the
        // site's own pagination links carry; matching is substring-based
        // regardless of the Bselect value (verified empirically).
        components.queryItems = [
            URLQueryItem(name: "Aselect", value: "2"),
            URLQueryItem(name: "Bselect", value: "3"),
            URLQueryItem(name: "Keyword", value: keyword),
        ]
        guard let url = components.url else { throw UtaNetError.invalidURL }
        return try await html(from: url)
    }

    public func lyricsPage(songID: Int) async throws -> String {
        guard let url = URL(string: "\(baseURL)/song/\(songID)/") else { throw UtaNetError.invalidURL }
        return try await html(from: url)
    }
}

extension UtaNetAPI {
    public static var baseURL: String { "https://www.uta-net.com" }

    private func html(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UtaNetError.httpStatus(http.statusCode)
        }
        guard let page = String(data: data, encoding: .utf8) else {
            throw UtaNetError.notUTF8
        }
        return page
    }
}

public enum UtaNetError: Error, Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case notUTF8
}

extension UtaNetError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "invalid uta-net URL"
        case .httpStatus(let code): "HTTP \(code)"
        case .notUTF8: "response body is not valid UTF-8"
        }
    }
}
