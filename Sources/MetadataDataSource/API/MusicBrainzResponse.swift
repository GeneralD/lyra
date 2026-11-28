public struct MusicBrainzResponse: Sendable {
    public let recordings: [MusicBrainzRecording]
}

extension MusicBrainzResponse: Decodable {}
