public struct ScreenState {
    public let layout: ScreenLayout
    public let isOccluded: Bool
    /// The screen `isOccluded` was measured against, so a caller holding a
    /// hysteresis flag across calls can tell whether it still applies to the
    /// same screen or must be re-scoped to a newly-selected one (#355).
    public let screen: ScreenInfo?

    public init(layout: ScreenLayout, isOccluded: Bool, screen: ScreenInfo? = nil) {
        self.layout = layout
        self.isOccluded = isOccluded
        self.screen = screen
    }
}

extension ScreenState: Sendable, Equatable {}
