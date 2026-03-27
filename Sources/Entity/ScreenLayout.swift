import CoreGraphics

public struct ScreenLayout {
    public let windowFrame: CGRect
    public let hostingFrame: CGRect
    public let screenOrigin: CGPoint

    public init(windowFrame: CGRect = .zero, hostingFrame: CGRect = .zero, screenOrigin: CGPoint = .zero) {
        self.windowFrame = windowFrame
        self.hostingFrame = hostingFrame
        self.screenOrigin = screenOrigin
    }
}

extension ScreenLayout: Sendable {}
