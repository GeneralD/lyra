import CoreGraphics
import Domain

extension ScreenInfo {
    /// Tolerance for treating a union area within this fraction of
    /// `visibleArea` as full coverage. Multiple windows that exactly tile a
    /// non-integer-origin `visibleFrame` can leave the coordinate-compressed
    /// union sum a few ULPs short of the visible area (windows whose shared
    /// edge is computed from different arithmetic paths, e.g. `a + w` vs.
    /// `a + 2w`, don't always land on the identical `Double`), so `unionArea /
    /// visibleArea` can land at e.g. `0.9999999999999996` instead of `1.0`.
    /// Left unhandled, a user-configured `threshold = 1.0` ("pause only when
    /// fully covered", a value `ConfigRepositoryImpl` accepts as valid) would
    /// never trigger for such a tiling (#355). The tolerance is far below any
    /// perceptible gap — even on a 4K-class screen, `1e-9` of the visible area
    /// is a small fraction of a single pixel.
    private static let fullCoverageTolerance = 1e-9

    /// Pure geometry: union area of window rects clipped to `visibleFrame`,
    /// divided by the visible frame's area. Unlike `occupancy(windows:)`, this
    /// does not double-count overlapping windows — the union is computed via
    /// coordinate compression: the clipped rects' x/y edges partition the plane
    /// into cells, and a cell's area counts once if any rect contains its center.
    func coverage(windows: [CGRect]) -> Double {
        let visibleArea = visibleFrame.width * visibleFrame.height
        guard visibleArea > 0 else { return 1 }

        let clipped =
            windows
            .map { $0.intersection(visibleFrame) }
            .filter { !$0.isNull && !$0.isEmpty }
        guard !clipped.isEmpty else { return 0 }

        let xs = clipped.flatMap { [$0.minX, $0.maxX] }.sorted()
        let ys = clipped.flatMap { [$0.minY, $0.maxY] }.sorted()

        let unionArea = zip(xs, xs.dropFirst()).reduce(0.0) { columnsArea, xEdges in
            let (x0, x1) = xEdges
            let columnWidth = x1 - x0
            guard columnWidth > 0 else { return columnsArea }

            let columnHeight = zip(ys, ys.dropFirst()).reduce(0.0) { rowsHeight, yEdges in
                let (y0, y1) = yEdges
                let cellHeight = y1 - y0
                guard cellHeight > 0 else { return rowsHeight }

                let cellCenter = CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2)
                let isCellCovered = clipped.contains { $0.contains(cellCenter) }
                return rowsHeight + (isCellCovered ? cellHeight : 0)
            }

            return columnsArea + columnWidth * columnHeight
        }

        let ratio = unionArea / visibleArea
        return ratio >= 1 - Self.fullCoverageTolerance ? 1 : ratio
    }
}
