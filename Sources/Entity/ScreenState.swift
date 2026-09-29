public struct ScreenState {
    public let layout: ScreenLayout
    public let isOccluded: Bool

    public init(layout: ScreenLayout, isOccluded: Bool) {
        self.layout = layout
        self.isOccluded = isOccluded
    }
}

extension ScreenState: Sendable, Equatable {}
