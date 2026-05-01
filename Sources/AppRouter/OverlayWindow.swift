@preconcurrency import AVFoundation
import Domain
import Views

@MainActor
protocol OverlayWindow: AnyObject {
    func show()
    func applyLayout(_ layout: ScreenLayout)
    func attachPlayerLayer(for player: AVPlayer)
    func applyWallpaperScale(_ scale: Double)
    func close()
}

extension AppWindow: OverlayWindow {}
