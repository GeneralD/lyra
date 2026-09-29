import CoreGraphics
import Domain

extension ScreenInfo {
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

        return min(unionArea / visibleArea, 1)
    }
}
