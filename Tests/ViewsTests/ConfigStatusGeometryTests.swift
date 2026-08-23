import Foundation
import Testing

@testable import Views

@Suite("ConfigStatusGeometry.isBroken")
struct ConfigStatusGeometryIsBrokenTests {
    private let geometry = ConfigStatusGeometry()

    @Test("index が7の倍数のとき欠損（missing strut）とみなす", arguments: [0, 7, 14, 21, 70])
    func multiplesOfSevenAreBroken(index: Int) {
        #expect(geometry.isBroken(index))
    }

    @Test("7の倍数以外は欠損しない", arguments: [1, 2, 3, 4, 5, 6, 8, 13, 15, 20])
    func othersAreNotBroken(index: Int) {
        #expect(!geometry.isBroken(index))
    }
}

@Suite("ConfigStatusGeometry.jitter")
struct ConfigStatusGeometryJitterTests {
    private let geometry = ConfigStatusGeometry()

    @Test("乱数を使わず、同じ index には常に同じ値を返す（決定的）")
    func deterministic() {
        #expect(geometry.jitter(for: 3) == geometry.jitter(for: 3))
        #expect(geometry.jitter(for: 12) == geometry.jitter(for: 12))
        #expect(geometry.jitter(for: 0) == geometry.jitter(for: 0))
    }

    @Test("jitter の絶対値は振幅（0.12）を超えない")
    func boundedByAmplitude() {
        for index in 0..<50 {
            #expect(abs(geometry.jitter(for: index)) <= 0.12 + 1e-9)
        }
    }
}

@Suite("ConfigStatusGeometry.project")
struct ConfigStatusGeometryProjectTests {
    private let geometry = ConfigStatusGeometry()

    @Test("angle=0 での回転・傾き・ジッタを反映した投影座標と深度を返す")
    func projectsWithTiltAndJitter() {
        let v = Vertex3D(x: 0.6, y: 0.2, z: 0.8)
        let center = CGPoint(x: 100, y: 60)
        let radius: CGFloat = 40
        let angle = 0.0
        let index = 5

        let result = geometry.project(v, center: center, radius: radius, angle: angle, index: index)

        // angle == 0 leaves x/z untouched by the spin rotation, so only the
        // fixed tilt (0.42 rad, mirroring the gold loading sphere) and the
        // deterministic per-index jitter should shape the result.
        let x1 = v.x
        let z1 = v.z
        let tilt = 0.42
        let y2 = v.y * cos(tilt) - z1 * sin(tilt)
        let z2 = v.y * sin(tilt) + z1 * cos(tilt)
        let jitteredRadius = radius * CGFloat(1 + geometry.jitter(for: index))
        let expectedPoint = CGPoint(
            x: center.x + jitteredRadius * CGFloat(x1),
            y: center.y - jitteredRadius * CGFloat(y2))

        #expect(abs(result.point.x - expectedPoint.x) < 1e-6)
        #expect(abs(result.point.y - expectedPoint.y) < 1e-6)
        #expect(abs(result.depth - z2) < 1e-6)
    }

    @Test("index が異なればジッタにより投影半径（中心からの距離）も変わる")
    func differentIndicesDisplaceRadiusDifferently() {
        let v = Vertex3D(x: 1, y: 0, z: 0)
        let center = CGPoint.zero
        let radius: CGFloat = 50

        let p1 = geometry.project(v, center: center, radius: radius, angle: 0, index: 1)
        let p2 = geometry.project(v, center: center, radius: radius, angle: 0, index: 2)

        let d1 = (p1.point.x * p1.point.x + p1.point.y * p1.point.y).squareRoot()
        let d2 = (p2.point.x * p2.point.x + p2.point.y * p2.point.y).squareRoot()
        #expect(abs(d1 - d2) > 1e-6)
    }
}

@Suite("ConfigStatusGeometry.edges")
struct ConfigStatusGeometryEdgesTests {
    private let geometry = ConfigStatusGeometry()

    @Test("欠損 index（7の倍数）は結果から除外される")
    func dropsBrokenEdges() {
        let size = CGSize(width: 120, height: 120)
        let edges = geometry.edges(in: size, time: 0)

        let totalEdges = GeodesicGeometry.edges.count
        let brokenCount = (0..<totalEdges).filter { geometry.isBroken($0) }.count
        #expect(edges.count == totalEdges - brokenCount)
        #expect(!edges.isEmpty)
    }

    @Test("遠い順（depth合計が小さい順）にソートされている")
    func sortedBackToFront() {
        let size = CGSize(width: 120, height: 120)
        let edges = geometry.edges(in: size, time: 1.23)

        let depths = edges.map { $0.start.depth + $0.end.depth }
        #expect(depths == depths.sorted())
    }

    @Test("time が変わると同じ index の投影点も変わる（回転が反映される）")
    func rotatesOverTime() {
        let size = CGSize(width: 120, height: 120)
        let edgesAtZero = geometry.edges(in: size, time: 0)
        let edgesLater = geometry.edges(in: size, time: 5)

        #expect(edgesAtZero != edgesLater)
    }
}
