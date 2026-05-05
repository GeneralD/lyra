import AppKit
import Combine
import Dependencies
import Domain
import Presenters
import SwiftUI
import Testing

@testable import Views

@MainActor
private func render<Content: View>(_ view: Content, size: CGSize) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    _ = hostingView.fittingSize
    if let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
    }
    // ImageRenderer materializes SwiftUI views to a CGImage, which forces
    // Canvas/TimelineView closures to run synchronously even outside a window.
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    _ = renderer.cgImage
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Stubs

private struct IdleTrackInteractor: TrackInteractor, @unchecked Sendable {
    let trackChange: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    let artwork: AnyPublisher<Data?, Never> = Empty().eraseToAnyPublisher()
    let playbackPosition: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect { .init(duration: 0) }
    var textLayout: TextLayout { .init(decodeEffect: .init(duration: 0)) }
    var artworkStyle: ArtworkStyle { .init() }
}

private struct DisabledRippleInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle { .init(enabled: false) }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private struct EnabledRippleInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle { .init(enabled: true) }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private struct PolygonRippleInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle {
        .init(enabled: true, shape: .polygon(sides: 6, angle: 15))
    }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private struct FixtureTrackInteractor: TrackInteractor, @unchecked Sendable {
    let title: String
    let artist: String
    let lyrics: [String]
    var artworkData: Data? = nil
    var opacity: Double = 1.0

    var trackChange: AnyPublisher<TrackUpdate, Never> {
        Just(
            TrackUpdate(
                title: title,
                artist: artist,
                lyrics: .plain(lyrics),
                lyricsState: .resolved
            )
        ).eraseToAnyPublisher()
    }
    var artwork: AnyPublisher<Data?, Never> { Just(artworkData).eraseToAnyPublisher() }
    let playbackPosition: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect { .init(duration: 0) }
    var textLayout: TextLayout { .init(decodeEffect: .init(duration: 0)) }
    var artworkStyle: ArtworkStyle { .init(opacity: opacity) }
}

// MARK: - HeaderView

@MainActor
@Suite("HeaderView rendering")
struct HeaderViewRenderingTests {
    @Test("idle state renders empty body")
    func idleState() {
        let presenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            HeaderPresenter()
        }
        // Don't call start() — titleState stays .idle
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
        #expect(presenter.titleState == .idle)
    }

    @Test("artwork hidden when opacity is 0")
    func artworkHidden() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: [], opacity: 0)
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayTitle == "Song" }

        #expect(presenter.artworkOpacity == 0)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }

    @Test("artwork placeholder when no image data")
    func artworkPlaceholder() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: [])
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayTitle == "Song" }

        #expect(presenter.artworkOpacity > 0)
        #expect(presenter.artworkData == nil)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }

    @Test("artwork image rendered with valid data")
    func artworkWithImage() async {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        let pngData = image.tiffRepresentation!

        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(
                title: "Song", artist: "Artist", lyrics: [], artworkData: pngData
            )
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.artworkData != nil && presenter.displayTitle == "Song" }

        #expect(presenter.artworkData != nil)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }
}

// MARK: - RippleView

@MainActor
@Suite("RippleView rendering")
struct RippleViewRenderingTests {
    @Test("disabled ripple renders empty body")
    func disabledRipple() {
        let presenter = withDependencies {
            $0.wallpaperInteractor = DisabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        presenter.start()
        defer { presenter.stop() }

        #expect(!presenter.isEnabled)
        render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
    }

    @Test("enabled ripple renders canvas")
    func enabledRipple() {
        let presenter = withDependencies {
            $0.wallpaperInteractor = EnabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        presenter.start()
        defer { presenter.stop() }

        #expect(presenter.isEnabled)
        #expect(presenter.rippleState != nil)
        render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
    }

    @Test("polygon ripple renders without crashing")
    func polygonRipple() {
        withDependencies {
            $0.wallpaperInteractor = PolygonRippleInteractor()
            // Use real time so the seeded ripple's startTime is close to
            // TimelineView's current frame time and survives the elapsed-vs-duration filter.
            $0.date = .init(Date.init)
        } operation: {
            let presenter = RipplePresenter()
            presenter.start()
            defer { presenter.stop() }

            #expect(presenter.rippleConfig.shape == .polygon(sides: 6, angle: 15))
            // Seed an active ripple so the Canvas drawing closure exercises stroke().
            presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 150))
            #expect(
                !presenter.drawingContexts(canvasSize: CGSize(width: 400, height: 300), now: Date())
                    .isEmpty)
            render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
        }
    }

    @Test("circle ripple stroke executes for active ripples")
    func circleRippleStrokeRuns() {
        withDependencies {
            $0.wallpaperInteractor = EnabledRippleInteractor()
            $0.date = .init(Date.init)
        } operation: {
            let presenter = RipplePresenter()
            presenter.start()
            defer { presenter.stop() }

            presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))
            #expect(
                !presenter.drawingContexts(canvasSize: CGSize(width: 400, height: 300), now: Date())
                    .isEmpty)
            render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
        }
    }
}

// MARK: - ripplePath geometry

private func collectedPoints(_ path: Path) -> [CGPoint] {
    var points: [CGPoint] = []
    // swift-format-ignore: ReplaceForEachWithForLoop
    // Path is not a Sequence; `forEach` is its only public element traversal API.
    path.forEach { element in
        switch element {
        case .move(let p), .line(let p):
            points.append(p)
        default:
            break
        }
    }
    return points
}

private func approxEqual(_ a: CGPoint, _ b: CGPoint, tolerance: Double = 1e-6) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

@Suite("ripplePath geometry")
struct RipplePathGeometryTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test("circle path encloses the given rect as an ellipse")
    func circleBounds() {
        let path = ripplePath(in: rect, shape: .circle)
        // SwiftUI's Path(ellipseIn:) exposes its bounds equal to the input rect.
        #expect(path.boundingRect == rect)
    }

    @Test("triangle has 3 distinct vertices, top vertex straight up")
    func triangleVertices() {
        let path = ripplePath(in: rect, shape: .polygon(sides: 3, angle: 0))
        let points = collectedPoints(path)
        #expect(points.count == 3)
        // angle = 0 => first vertex is straight up at (midX, midY - radius).
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        #expect(approxEqual(points[0], CGPoint(x: center.x, y: center.y - radius)))
    }

    @Test("square at angle=0 forms a diamond (vertices on axes)")
    func squareDiamondVertices() {
        let path = ripplePath(in: rect, shape: .polygon(sides: 4, angle: 0))
        let points = collectedPoints(path)
        #expect(points.count == 4)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Going clockwise from top: (cx, cy-r), (cx+r, cy), (cx, cy+r), (cx-r, cy).
        #expect(approxEqual(points[0], CGPoint(x: center.x, y: center.y - radius)))
        #expect(approxEqual(points[1], CGPoint(x: center.x + radius, y: center.y)))
        #expect(approxEqual(points[2], CGPoint(x: center.x, y: center.y + radius)))
        #expect(approxEqual(points[3], CGPoint(x: center.x - radius, y: center.y)))
    }

    @Test("square at angle=45 forms an axis-aligned square")
    func squareRotated45() {
        let path = ripplePath(in: rect, shape: .polygon(sides: 4, angle: 45))
        let points = collectedPoints(path)
        #expect(points.count == 4)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let s = radius * sin(Double.pi / 4)
        #expect(approxEqual(points[0], CGPoint(x: center.x + s, y: center.y - s)))
        #expect(approxEqual(points[1], CGPoint(x: center.x + s, y: center.y + s)))
        #expect(approxEqual(points[2], CGPoint(x: center.x - s, y: center.y + s)))
        #expect(approxEqual(points[3], CGPoint(x: center.x - s, y: center.y - s)))
    }

    @Test("hexagon has 6 vertices on circumscribed circle")
    func hexagonOnCircle() {
        let path = ripplePath(in: rect, shape: .polygon(sides: 6, angle: 0))
        let points = collectedPoints(path)
        #expect(points.count == 6)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for p in points {
            let d = sqrt(pow(p.x - center.x, 2) + pow(p.y - center.y, 2))
            #expect(abs(d - radius) < 1e-6)
        }
    }

    @Test("polygon with sides below minimum falls back to circle")
    func tooFewSidesFallsBack() {
        let circlePath = ripplePath(in: rect, shape: .circle)
        let fallback = ripplePath(in: rect, shape: .polygon(sides: 0, angle: 0))
        #expect(fallback.boundingRect == circlePath.boundingRect)
    }

    @Test("polygon with sides above maximum is clamped to maximum")
    func tooManySidesClamped() {
        let path = ripplePath(in: rect, shape: .polygon(sides: 10_000, angle: 0))
        let points = collectedPoints(path)
        #expect(points.count == RippleShape.maximumPolygonSides)
    }
}

// MARK: - LyricsColumnView

@MainActor
@Suite("LyricsColumnView rendering")
struct LyricsColumnViewRenderingTests {
    @Test("empty lyrics renders without crash")
    func emptyLyrics() {
        let presenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            LyricsPresenter()
        }
        render(LyricsColumnView(presenter: presenter), size: CGSize(width: 600, height: 300))
    }

    @Test("populated lyrics renders lines")
    func populatedLyrics() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: ["Line 1", "Line 2", "Line 3"])
        } operation: {
            LyricsPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayLyricLines == ["Line 1", "Line 2", "Line 3"] }

        render(LyricsColumnView(presenter: presenter), size: CGSize(width: 600, height: 300))
        #expect(presenter.displayLyricLines == ["Line 1", "Line 2", "Line 3"])
    }
}

// MARK: - OverlayContentView wallpaper loading

private struct PendingWallpaperInteractor: WallpaperInteractor, @unchecked Sendable {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle { .init(enabled: false) }
    /// Stream that never yields and never finishes — keeps WallpaperPresenter.isLoading == true.
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> {
        AsyncStream { _ in }
    }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
@Suite("OverlayContentView wallpaper loading indicator")
struct OverlayContentViewLoadingTests {
    @Test("renders with idle wallpaper presenter (no loading state)")
    func rendersWithIdlePresenter() async {
        let headerPresenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            HeaderPresenter()
        }
        let lyricsPresenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            LyricsPresenter()
        }
        let ripplePresenter = withDependencies {
            $0.wallpaperInteractor = DisabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        let wallpaperPresenter = withDependencies {
            $0.wallpaperInteractor = DisabledRippleInteractor()
        } operation: {
            WallpaperPresenter()
        }

        // Don't call wallpaperPresenter.start() — isLoading stays false
        #expect(wallpaperPresenter.isLoading == false)
        render(
            OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter,
                wallpaperPresenter: wallpaperPresenter
            ),
            size: CGSize(width: 800, height: 500)
        )
    }

    @Test("renders with loading wallpaper presenter (pending download)")
    func rendersWithLoadingPresenter() async {
        let headerPresenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            HeaderPresenter()
        }
        let lyricsPresenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            LyricsPresenter()
        }
        let ripplePresenter = withDependencies {
            $0.wallpaperInteractor = DisabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        let wallpaperPresenter = withDependencies {
            $0.wallpaperInteractor = PendingWallpaperInteractor()
            $0.continuousClock = ImmediateClock()
        } operation: {
            WallpaperPresenter()
        }

        wallpaperPresenter.start()
        defer { wallpaperPresenter.stop() }

        #expect(wallpaperPresenter.isLoading == true)
        render(
            OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter,
                wallpaperPresenter: wallpaperPresenter
            ),
            size: CGSize(width: 800, height: 500)
        )
    }
}
