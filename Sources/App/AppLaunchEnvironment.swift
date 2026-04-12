import Foundation

public struct AppLaunchEnvironment: Sendable, Equatable {
    public enum Keys {
        public static let uiTestMode = "LYRA_UI_TEST_MODE"
        public static let lyricsTitle = "LYRA_UI_TEST_TITLE"
        public static let lyricsArtist = "LYRA_UI_TEST_ARTIST"
        public static let lyricsLines = "LYRA_UI_TEST_LYRICS"
    }

    public let isUITestMode: Bool
    public let title: String
    public let artist: String
    public let lyricsLines: [String]

    public init(environment: [String: String]) {
        isUITestMode = Self.parseBoolean(environment[Keys.uiTestMode])
        title = environment[Keys.lyricsTitle] ?? "UI Test Song"
        artist = environment[Keys.lyricsArtist] ?? "UI Test Artist"
        lyricsLines = Self.parseLyrics(environment[Keys.lyricsLines])
    }

    public static var current: Self {
        .init(environment: ProcessInfo.processInfo.environment)
    }

    private static func parseBoolean(_ value: String?) -> Bool {
        switch value?.lowercased() {
        case "1", "true", "yes", "on": true
        default: false
        }
    }

    private static func parseLyrics(_ value: String?) -> [String] {
        let defaultLines = ["First UI test lyric", "Second UI test lyric"]
        guard let value else { return defaultLines }

        let lines =
            value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? defaultLines : lines
    }
}
