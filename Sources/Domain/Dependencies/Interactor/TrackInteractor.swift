// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Combine
import Dependencies
import Foundation

public protocol TrackInteractor: Sendable {
    /// Emits once per track change, after metadata + lyrics resolution.
    var trackChange: AnyPublisher<TrackUpdate, Never> { get }
    /// Emits when artwork data changes.
    var artwork: AnyPublisher<Data?, Never> { get }
    /// Emits continuously for playback position updates.
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { get }
    var decodeEffectConfig: DecodeEffect { get }
    var textLayout: TextLayout { get }
    var artworkStyle: ArtworkStyle { get }
}

public enum TrackInteractorKey: TestDependencyKey {
    public static let testValue: any TrackInteractor = UnimplementedTrackInteractor()
}

extension DependencyValues {
    public var trackInteractor: any TrackInteractor {
        get { self[TrackInteractorKey.self] }
        set { self[TrackInteractorKey.self] = newValue }
    }
}

private struct UnimplementedTrackInteractor: TrackInteractor {
    var trackChange: AnyPublisher<TrackUpdate, Never> { Empty().eraseToAnyPublisher() }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
    var decodeEffectConfig: DecodeEffect { .init() }
    var textLayout: TextLayout { .init() }
    var artworkStyle: ArtworkStyle { .init() }
}