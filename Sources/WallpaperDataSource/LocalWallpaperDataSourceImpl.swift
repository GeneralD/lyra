import Domain
import Files
import Foundation

public struct LocalWallpaperDataSourceImpl: Sendable {
    public init() {}
}

extension LocalWallpaperDataSourceImpl: WallpaperDataSource {
    public func resolve(_ location: LocalWallpaper) async throws -> String {
        guard !location.path.hasPrefix("/") else { return location.path }
        guard let file = try? Folder(path: location.configDir).file(at: location.path) else {
            return URL(fileURLWithPath: location.configDir).appendingPathComponent(location.path).path
        }
        return file.path
    }
}
