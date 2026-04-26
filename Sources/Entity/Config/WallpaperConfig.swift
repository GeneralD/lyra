import Foundation

public struct WallpaperConfig {
    public let items: [WallpaperItemConfig]
    public let mode: WallpaperPlaybackMode

    public init(items: [WallpaperItemConfig], mode: WallpaperPlaybackMode = .cycle) {
        self.items = items
        self.mode = mode
    }

    /// Convenience for single-item config (backward-compatible with legacy call sites).
    public init(location: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.items = [WallpaperItemConfig(location: location, start: start, end: end)]
        self.mode = .cycle
    }
}

extension WallpaperConfig: Sendable {}
extension WallpaperConfig: Equatable {}

extension WallpaperConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case items, mode
        case location, start, end
    }

    /// Decodes three shapes:
    /// - Bare string: `wallpaper = "clip.mp4"` → single item, no trim, cycle
    /// - Legacy table: `[wallpaper] location = "x" start = "0:10" end = "0:40"` → single item with trim
    /// - Multi table: `[wallpaper] mode = "shuffle" [[wallpaper.items]] ...` → items array
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let value = try? container.decode(String.self)
        {
            items = [WallpaperItemConfig(location: value)]
            mode = .cycle
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(WallpaperPlaybackMode.self, forKey: .mode) ?? .cycle
        if let itemsArray = try c.decodeIfPresent([WallpaperItemConfig].self, forKey: .items),
            !itemsArray.isEmpty
        {
            items = itemsArray
            return
        }
        let location = try c.decode(String.self, forKey: .location)
        let rawStart = try c.decodeIfPresent(String.self, forKey: .start).flatMap(WallpaperItemConfig.parseTime)
        let rawEnd = try c.decodeIfPresent(String.self, forKey: .end).flatMap(WallpaperItemConfig.parseTime)
        let (validatedStart, validatedEnd) = WallpaperItemConfig.validate(start: rawStart, end: rawEnd)
        items = [WallpaperItemConfig(location: location, start: validatedStart, end: validatedEnd)]
    }

    public func encode(to encoder: Encoder) throws {
        if items.count == 1, mode == .cycle {
            try items[0].encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(items, forKey: .items)
    }
}
