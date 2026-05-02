import AppKit
import Combine
import Dependencies
import Domain
import Foundation

public struct WallpaperInteractorImpl {
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.wallpaperUseCase) private var wallpaperService

    public init() {}
}

extension WallpaperInteractorImpl: WallpaperInteractor {
    public var playbackMode: WallpaperPlaybackMode {
        configService.appStyle.wallpaper?.mode ?? .cycle
    }

    public func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> {
        let appStyle = configService.appStyle
        guard let wallpaper = appStyle.wallpaper, !wallpaper.items.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        let configDir = appStyle.configDir ?? FileManager.default.homeDirectoryForCurrentUser.path
        let items = wallpaper.items
        let mode = wallpaper.mode
        let service = wallpaperService
        return AsyncStream { continuation in
            let task = Task {
                switch mode {
                case .cycle:
                    await Self.emitInOrder(items: items, configDir: configDir, service: service, into: continuation)
                case .shuffle:
                    await Self.emitAsCompleted(items: items, configDir: configDir, service: service, into: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var rippleConfig: RippleStyle {
        configService.appStyle.ripple
    }

    public var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> {
        let ws = NSWorkspace.shared.notificationCenter
        let sleep = ws.publisher(for: NSWorkspace.screensDidSleepNotification)
            .map { _ in SleepWakeEvent.willSleep }
        let wake = ws.publisher(for: NSWorkspace.screensDidWakeNotification)
            .map { _ in SleepWakeEvent.didWake }
        return sleep.merge(with: wake).eraseToAnyPublisher()
    }
}

extension WallpaperInteractorImpl {
    private enum ResolutionSlot {
        case pending
        case resolved(ResolvedWallpaperItem)
        case failed
    }

    /// Kick off parallel resolution, emit in configuration order. Buffers out-of-order completions.
    private static func emitInOrder(
        items: [WallpaperItem],
        configDir: String,
        service: any WallpaperUseCase,
        into continuation: AsyncStream<ResolvedWallpaperItem>.Continuation
    ) async {
        await withTaskGroup(of: (Int, ResolvedWallpaperItem?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let url = try? await service.resolveWallpaper(value: item.location, configDir: configDir)
                    return (
                        index,
                        url.map {
                            ResolvedWallpaperItem(
                                url: $0,
                                start: item.start,
                                end: item.end,
                                scale: item.scale)
                        }
                    )
                }
            }
            var buffer = Array(repeating: ResolutionSlot.pending, count: items.count)
            var nextExpected = 0
            for await (index, resolved) in group {
                buffer[index] = resolved.map(ResolutionSlot.resolved) ?? .failed
                emit: while nextExpected < buffer.count {
                    switch buffer[nextExpected] {
                    case .pending:
                        break emit
                    case .resolved(let item):
                        continuation.yield(item)
                        nextExpected += 1
                    case .failed:
                        nextExpected += 1
                    }
                }
            }
        }
    }

    /// Kick off parallel resolution, emit as each completes (shuffle mode: first to arrive plays first).
    private static func emitAsCompleted(
        items: [WallpaperItem],
        configDir: String,
        service: any WallpaperUseCase,
        into continuation: AsyncStream<ResolvedWallpaperItem>.Continuation
    ) async {
        await withTaskGroup(of: ResolvedWallpaperItem?.self) { group in
            for item in items {
                group.addTask {
                    let url = try? await service.resolveWallpaper(value: item.location, configDir: configDir)
                    return url.map {
                        ResolvedWallpaperItem(
                            url: $0,
                            start: item.start,
                            end: item.end,
                            scale: item.scale)
                    }
                }
            }
            for await resolved in group {
                if let resolved { continuation.yield(resolved) }
            }
        }
    }
}
