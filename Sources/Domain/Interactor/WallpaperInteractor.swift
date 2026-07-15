import Combine
import Dependencies
import Foundation

public protocol WallpaperInteractor: Sendable {
    /// Playback mode for the configured wallpaper set. Presenter reads this once before subscribing.
    var playbackMode: WallpaperPlaybackMode { get }
    /// The current wallpaper source config (items + mode). The Presenter diffs this
    /// across config hot-reload pings to decide whether the wallpaper actually
    /// changed — an unrelated edit (e.g. header font) leaves the playing video
    /// untouched, while a real source change triggers a re-resolve. Nil when no
    /// wallpaper is configured.
    var wallpaperSource: WallpaperStyle? { get }
    /// Resolves configured wallpaper items and yields them as they become available.
    /// - For `.cycle`: emits in configured order (buffers out-of-order completions).
    /// - For `.shuffle`: emits as-completed — first successful resolution plays first.
    /// Empty stream means no wallpaper is configured or none resolved.
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem>
    var rippleConfig: RippleStyle { get }
    /// Emits when the system sleeps or wakes (e.g. display asleep/awake).
    /// Provider layer adapts the platform-native notification into a Publisher
    /// so the Presenter stays AppKit-free.
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { get }
}

public enum WallpaperInteractorKey: TestDependencyKey {
    public static let testValue: any WallpaperInteractor = UnimplementedWallpaperInteractor()
}

extension DependencyValues {
    public var wallpaperInteractor: any WallpaperInteractor {
        get { self[WallpaperInteractorKey.self] }
        set { self[WallpaperInteractorKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var wallpaperSource: WallpaperStyle? { nil }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> {
        AsyncStream { $0.finish() }
    }
    var rippleConfig: RippleStyle { .init() }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> {
        Empty().eraseToAnyPublisher()
    }
}
