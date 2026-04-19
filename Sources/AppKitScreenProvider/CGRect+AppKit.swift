import CoreGraphics

extension CGRect {
    /// Window bounds from `CGWindowListCopyWindowInfo` are in CoreGraphics coordinates
    /// (origin = top-left of primary display, y grows downward), while `NSScreen.frame`
    /// is in AppKit coordinates (origin = bottom-left of primary display, y grows upward).
    /// Flip y so the intersection with `NSScreen.frame` is geometrically correct.
    func flippedToAppKit(primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: primaryHeight - origin.y - height,
            width: width,
            height: height
        )
    }
}
