import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain
import Foundation

struct TrackCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "track",
        abstract: "Show currently playing track info as JSON"
    )

    @Flag(name: [.short, .long], help: "Resolve metadata via MusicBrainz/regex")
    var resolve = false

    @Flag(name: [.short, .long], help: "Include lyrics (fetches from LRCLIB)")
    var lyrics = false

    func run() async throws {
        @Dependency(\.trackHandler) var handler
        let info = await handler.fetchInfo(query: TrackQuery(resolve: resolve, lyrics: lyrics))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(info)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}
