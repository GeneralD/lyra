import Foundation
import Testing

@testable import Entity

@Suite("Wallpaper scale")
struct WallpaperScaleTests {
    @Test("WallpaperItem defaults scale to 1.0")
    func wallpaperItemDefaultScale() {
        #expect(WallpaperItem(location: "bg.mp4").scale == 1.0)
    }

    @Test("WallpaperItem clamps invalid scale values")
    func wallpaperItemClampsInvalidScale() {
        #expect(WallpaperItem(location: "bg.mp4", scale: 0.5).scale == 1.0)
        #expect(WallpaperItem(location: "bg.mp4", scale: .nan).scale == 1.0)
    }

    @Test("ResolvedWallpaperItem defaults scale to 1.0")
    func resolvedItemDefaultScale() {
        let item = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/bg.mp4"))
        #expect(item.scale == 1.0)
    }

    @Test("ResolvedWallpaperItem clamps invalid scale values")
    func resolvedItemClampsInvalidScale() {
        let url = URL(fileURLWithPath: "/tmp/bg.mp4")
        #expect(ResolvedWallpaperItem(url: url, scale: 0.5).scale == 1.0)
        #expect(ResolvedWallpaperItem(url: url, scale: .nan).scale == 1.0)
    }
}
