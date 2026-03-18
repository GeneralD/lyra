import Dependencies

public protocol TitleExtractor: Sendable {
    func extract(rawTitle: String, rawArtist: String) async -> [ResolvedTrack]
}

public enum TitleExtractorKey: TestDependencyKey {
    public static let testValue: [any TitleExtractor] = []
}

extension DependencyValues {
    public var titleExtractors: [any TitleExtractor] {
        get { self[TitleExtractorKey.self] }
        set { self[TitleExtractorKey.self] = newValue }
    }
}
