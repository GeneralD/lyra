// MARK: - Geodesic sphere geometry

/// A point on the unit sphere. Internal (not `private`) so the pure geometry in
/// `GeodesicGeometry` can be unit-tested via `@testable import Views`.
struct Vertex3D {
    let x, y, z: Double
}

/// Wireframe edges of a gold geodesic sphere. The geometry is the DUAL of a
/// once-subdivided icosphere: start from an icosahedron, subdivide each of its
/// 20 triangles into 4 (an 80-triangle "icosphere"), then connect the centroid
/// of every triangle to its edge-neighbours. The result is a Goldberg
/// polyhedron — 12 pentagons + 30 hexagons, a soccer ball with a few extra
/// faces. Geometry is independent of rotation, so it is built once and reused
/// for every frame. Internal (not `private`) so the edge generation can be
/// unit-tested via `@testable import Views`.
enum GeodesicGeometry {
    static let edges: [(Vertex3D, Vertex3D)] = buildEdges()

    private static func normalized(_ v: Vertex3D) -> Vertex3D {
        let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        return Vertex3D(x: v.x / length, y: v.y / length, z: v.z / length)
    }

    /// Order-independent key for an undirected vertex pair.
    private static func key(_ a: Int, _ b: Int) -> Int64 {
        a < b ? (Int64(a) << 32) | Int64(b) : (Int64(b) << 32) | Int64(a)
    }

    private static func buildEdges() -> [(Vertex3D, Vertex3D)] {
        let t = (1 + 5.0.squareRoot()) / 2  // golden ratio
        var verts: [Vertex3D] = [
            Vertex3D(x: -1, y: t, z: 0), Vertex3D(x: 1, y: t, z: 0),
            Vertex3D(x: -1, y: -t, z: 0), Vertex3D(x: 1, y: -t, z: 0),
            Vertex3D(x: 0, y: -1, z: t), Vertex3D(x: 0, y: 1, z: t),
            Vertex3D(x: 0, y: -1, z: -t), Vertex3D(x: 0, y: 1, z: -t),
            Vertex3D(x: t, y: 0, z: -1), Vertex3D(x: t, y: 0, z: 1),
            Vertex3D(x: -t, y: 0, z: -1), Vertex3D(x: -t, y: 0, z: 1),
        ].map(normalized)
        let base: [[Int]] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        var cache: [Int64: Int] = [:]
        func mid(_ a: Int, _ b: Int) -> Int {
            let k = key(a, b)
            if let cached = cache[k] { return cached }
            let va = verts[a]
            let vb = verts[b]
            verts.append(
                normalized(
                    Vertex3D(x: (va.x + vb.x) / 2, y: (va.y + vb.y) / 2, z: (va.z + vb.z) / 2)))
            cache[k] = verts.count - 1
            return verts.count - 1
        }
        let faces = base.flatMap { f -> [[Int]] in
            let ab = mid(f[0], f[1])
            let bc = mid(f[1], f[2])
            let ca = mid(f[2], f[0])
            return [[f[0], ab, ca], [f[1], bc, ab], [f[2], ca, bc], [ab, bc, ca]]
        }
        let centroids = faces.map { f -> Vertex3D in
            let a = verts[f[0]]
            let b = verts[f[1]]
            let c = verts[f[2]]
            return normalized(
                Vertex3D(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3, z: (a.z + b.z + c.z) / 3))
        }
        var edgeFaces: [Int64: [Int]] = [:]
        for (index, f) in faces.enumerated() {
            for (u, v) in [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])] {
                edgeFaces[key(u, v), default: []].append(index)
            }
        }
        return edgeFaces.values.compactMap {
            $0.count == 2 ? (centroids[$0[0]], centroids[$0[1]]) : nil
        }
    }
}
