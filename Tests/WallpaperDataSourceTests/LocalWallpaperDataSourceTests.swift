import Domain
import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("LocalWallpaperDataSourceImpl", .serialized)
struct LocalWallpaperDataSourceTests {
    private let sut = LocalWallpaperDataSourceImpl()
    private let fm = FileManager.default

    private func makeTempDir() -> String {
        fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }

    // MARK: - Normal Behavior

    @Test("absolute path returned as-is regardless of configDir")
    func absolutePathReturnedAsIs() async throws {
        let tmp = makeTempDir()
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let absolutePath = "/some/absolute/video.mp4"
        let location = LocalWallpaper(path: absolutePath, configDir: tmp)
        let result = try await sut.resolve(location)

        #expect(result == absolutePath)
    }

    @Test("relative path resolved against configDir when file exists")
    func relativePathResolvedWhenFileExists() async throws {
        let tmp = makeTempDir()
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let fileName = "wallpaper.mp4"
        let filePath = (tmp as NSString).appendingPathComponent(fileName)
        fm.createFile(atPath: filePath, contents: nil)

        let location = LocalWallpaper(path: fileName, configDir: tmp)
        let result = try await sut.resolve(location)

        #expect(result == filePath)
    }

    // MARK: - Boundary Conditions

    @Test("path with ../ traversal resolved correctly when file exists")
    func pathWithTraversal() async throws {
        let tmp = makeTempDir()
        let subDir = (tmp as NSString).appendingPathComponent("sub")
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        let fileName = "wallpaper.mp4"
        let filePath = (tmp as NSString).appendingPathComponent(fileName)
        fm.createFile(atPath: filePath, contents: nil)

        let location = LocalWallpaper(path: "../\(fileName)", configDir: subDir)
        let result = try await sut.resolve(location)

        #expect(result == filePath)
    }

    @Test("relative path falls back to URL appendingPathComponent when file does not exist")
    func relativePathFallbackWhenFileDoesNotExist() async throws {
        let tmp = makeTempDir()
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let fileName = "nonexistent.mp4"
        let location = LocalWallpaper(path: fileName, configDir: tmp)
        let result = try await sut.resolve(location)

        let expected = URL(fileURLWithPath: tmp).appendingPathComponent(fileName).path
        #expect(result == expected)
    }

    @Test("path with spaces resolved correctly when file exists")
    func pathWithSpaces() async throws {
        let tmp = makeTempDir()
        defer { try? fm.removeItem(atPath: tmp) }
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let fileName = "my wallpaper file.mp4"
        let filePath = (tmp as NSString).appendingPathComponent(fileName)
        fm.createFile(atPath: filePath, contents: nil)

        let location = LocalWallpaper(path: fileName, configDir: tmp)
        let result = try await sut.resolve(location)

        #expect(result == filePath)
    }
}
