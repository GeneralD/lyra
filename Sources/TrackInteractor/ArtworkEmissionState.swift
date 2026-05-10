import Combine
import Domain
import Foundation

enum ArtworkEmission {
    case suppress
    case clear
    case set(Data)

    var publisher: AnyPublisher<Data?, Never> {
        switch self {
        case .suppress:
            return Empty<Data?, Never>(completeImmediately: true).eraseToAnyPublisher()
        case .clear:
            return Just<Data?>(nil).eraseToAnyPublisher()
        case .set(let artwork):
            return Just<Data?>(artwork).eraseToAnyPublisher()
        }
    }
}

struct ArtworkEmissionState {
    let track: TrackIdentity?
    let lastArtwork: Data?
    let emission: ArtworkEmission

    init(track: TrackIdentity? = nil, lastArtwork: Data? = nil, emission: ArtworkEmission = .suppress) {
        self.track = track
        self.lastArtwork = lastArtwork
        self.emission = emission
    }

    func advanced(with current: NowPlaying) -> Self {
        let currentTrack = TrackIdentity(current)
        guard let track, track == currentTrack else {
            return .init(track: currentTrack, lastArtwork: current.artworkData, emission: current.artworkData.map(ArtworkEmission.set) ?? .clear)
        }

        guard lastArtwork == nil, let currentArtwork = current.artworkData else {
            return .init(track: currentTrack, lastArtwork: lastArtwork)
        }

        return .init(
            track: currentTrack,
            lastArtwork: currentArtwork,
            emission: .set(currentArtwork)
        )
    }
}
