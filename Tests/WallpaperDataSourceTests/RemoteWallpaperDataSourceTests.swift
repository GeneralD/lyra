import Domain
import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("RemoteWallpaperDataSourceImpl")
struct RemoteWallpaperDataSourceTests {
    @Test("download success moves file to cache path")
    func downloadSuccess() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("video content".utf8).write(to: tempFile)

        let dataSource = RemoteWallpaperDataSourceImpl { url in
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (tempFile, response)
        }

        let url = try #require(URL(string: "https://example.com/bg.mp4"))
        let result = try await dataSource.resolve(RemoteWallpaper(url: url))

        #expect(FileManager.default.fileExists(atPath: result))
        #expect(result.hasSuffix(".mp4"))
        try? FileManager.default.removeItem(atPath: result)
    }

    @Test("HTTP error removes temp file and throws")
    func httpErrorCleansUp() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bad content".utf8).write(to: tempFile)

        let dataSource = RemoteWallpaperDataSourceImpl { url in
            let response = HTTPURLResponse(
                url: url, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (tempFile, response)
        }

        let url = try #require(URL(string: "https://example.com/bg.mp4"))
        await #expect(throws: URLError.self) {
            try await dataSource.resolve(RemoteWallpaper(url: url))
        }
        #expect(!FileManager.default.fileExists(atPath: tempFile.path))
    }

    @Test("download performer error propagates")
    func downloadError() async {
        let dataSource = RemoteWallpaperDataSourceImpl { _ in
            throw URLError(.notConnectedToInternet)
        }

        let url = URL(string: "https://example.com/bg.mp4")!
        await #expect(throws: URLError.self) {
            try await dataSource.resolve(RemoteWallpaper(url: url))
        }
    }
}
