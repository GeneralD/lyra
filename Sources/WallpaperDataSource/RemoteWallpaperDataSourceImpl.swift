import Domain
import Foundation

public struct RemoteWallpaperDataSourceImpl: Sendable {
    private let downloadPerformer: @Sendable (URL) async throws -> (URL, URLResponse)

    public init() {
        self.init { url in
            try await URLSession.shared.download(from: url)
        }
    }

    init(downloadPerformer: @escaping @Sendable (URL) async throws -> (URL, URLResponse)) {
        self.downloadPerformer = downloadPerformer
    }
}

extension RemoteWallpaperDataSourceImpl: WallpaperDataSource {
    /// Downloads to a temp file in the cache folder. Returns the temp file path.
    /// Cache deduplication is handled by WallpaperRepository.
    public func resolve(_ location: RemoteWallpaper) async throws -> String {
        let cache = try WallpaperCache()
        let tempPath = cache.tempPath(for: location.url)

        let (tempURL, response) = try await downloadPerformer(location.url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }

        let destURL = URL(fileURLWithPath: tempPath)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return tempPath
    }
}
