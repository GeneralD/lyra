import ConfigUseCase
import Dependencies
import Domain
import LyricsUseCase
import MetadataUseCase
import PlaybackUseCase

extension ConfigUseCaseKey: DependencyKey {
    public static let liveValue: any ConfigUseCase = ConfigUseCaseImpl()
}

extension LyricsUseCaseKey: DependencyKey {
    public static let liveValue: any LyricsUseCase = LyricsUseCaseImpl()
}

extension MetadataUseCaseKey: DependencyKey {
    public static let liveValue: any MetadataUseCase = MetadataUseCaseImpl()
}

extension PlaybackUseCaseKey: DependencyKey {
    public static let liveValue: any PlaybackUseCase = PlaybackUseCaseImpl()
}
