import CoreGraphics
import Domain

extension ScreenInfo {
    /// Pure geometry: sum the area of each window rect intersected with `frame`,
    /// divided by the screen's total area.
    func occupancy(windows: [CGRect]) -> Double {
        let screenArea = frame.width * frame.height
        guard screenArea > 0 else { return 1 }
        let covered =
            windows
            .map { $0.intersection(frame) }
            .filter { !$0.isNull && !$0.isEmpty }
            .reduce(0.0) { $0 + $1.width * $1.height }
        return covered / screenArea
    }
}
