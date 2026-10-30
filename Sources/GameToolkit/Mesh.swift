import VectorMath

/// A solid shape of flat triangles, in its own space, wound counterclockwise
/// as seen from outside.
public struct Mesh: Sendable {
    /// Each three positions are a triangle.
    public let positions: [Vector3<Float>]
    // The positions' coordinates in order, for appending without vectors.
    let coordinates: [Float]

    /// Triangles from `positions`, each three a triangle. A convex shape's
    /// triangles are wound to face away from its center, however given.
    public init(convex positions: [Vector3<Float>]) {
        precondition(positions.count.isMultiple(of: 3), "A mesh needs three positions for each triangle")
        let center = positions.reduce(Vector3<Float>.zero, +) / Float(max(positions.count, 1))
        var wound: [Vector3<Float>] = []
        for start in stride(from: 0, to: positions.count, by: 3) {
            let (a, b, c) = (positions[start], positions[start + 1], positions[start + 2])
            let normal = cross(b - a, c - a)
            wound += dot(normal, a - center) >= 0 ? [a, b, c] : [a, c, b]
        }
        self.positions = wound
        coordinates = wound.flatMap { [$0.x, $0.y, $0.z] }
    }

    /// A cube from -1 to 1 on each axis.
    public static let cube: Mesh = {
        let corners = (0..<8).map { index in
            Vector3<Float>(index & 1 == 0 ? -1 : 1, index & 2 == 0 ? -1 : 1, index & 4 == 0 ? -1 : 1)
        }
        // Each face's corners, in order around it.
        let faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
        return Mesh(convex: faces.flatMap { face in
            [corners[face[0]], corners[face[1]], corners[face[2]], corners[face[0]], corners[face[2]], corners[face[3]]]
        })
    }()

    /// An octahedron with its corners at 1 on each axis.
    public static let octahedron: Mesh = {
        let axes: [Vector3<Float>] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
        var positions: [Vector3<Float>] = []
        for x: Float in [-1, 1] {
            for y: Float in [-1, 1] {
                for z: Float in [-1, 1] {
                    positions += [axes[0] * x, axes[1] * y, axes[2] * z]
                }
            }
        }
        return Mesh(convex: positions)
    }()

    /// A pyramid on a square base from -1 to 1 in x and z at y -1, with its
    /// apex at y 1.
    public static let pyramid: Mesh = {
        let apex = Vector3<Float>(0, 1, 0)
        let base: [Vector3<Float>] = [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)]
        var positions = [base[0], base[1], base[2], base[0], base[2], base[3]]
        for index in base.indices {
            positions += [base[index], base[(index + 1) % 4], apex]
        }
        return Mesh(convex: positions)
    }()
}

/// Meshes to draw in 3D, each placed by a transform and in one color.
public struct MeshBatch {
    // Each vertex is a position and a normal in world space, and a color.
    static let floatsPerVertex = 10

    private(set) var vertices: [Float] = []

    var vertexCount: Int {
        vertices.count / Self.floatsPerVertex
    }

    public init() {}

    /// `mesh` moved into world space by `transform`, in a color with each
    /// component from 0 to 1. Each triangle is lit as flat.
    public mutating func append(_ mesh: Mesh, transform: Matrix4x4<Float>, color: Vector4<Float>) {
        // In scalars on raw buffers, as games append thousands of triangles a
        // frame and unoptimized builds, as in the browser, would take far
        // longer over vectors and arrays.
        let (c0, c1, c2, c3) = transform.columns
        let m = (
            c0.x, c0.y, c0.z, c1.x, c1.y, c1.z, c2.x, c2.y, c2.z, c3.x, c3.y, c3.z
        )
        let (r, g, b, alpha) = (color.r, color.g, color.b, color.a)
        let triangleCount = mesh.coordinates.count / 9
        let added = [Float](unsafeUninitializedCapacity: triangleCount * 3 * Self.floatsPerVertex) {
            vertices, initializedCount in
            mesh.coordinates.withUnsafeBufferPointer { source in
                var output = 0
                for triangle in 0..<triangleCount {
                    let input = triangle * 9
                    // The triangle's corners in world space.
                    var x0 = source[input], y0 = source[input + 1], z0 = source[input + 2]
                    var x1 = source[input + 3], y1 = source[input + 4], z1 = source[input + 5]
                    var x2 = source[input + 6], y2 = source[input + 7], z2 = source[input + 8]
                    (x0, y0, z0) = (
                        m.0 * x0 + m.3 * y0 + m.6 * z0 + m.9, m.1 * x0 + m.4 * y0 + m.7 * z0 + m.10,
                        m.2 * x0 + m.5 * y0 + m.8 * z0 + m.11
                    )
                    (x1, y1, z1) = (
                        m.0 * x1 + m.3 * y1 + m.6 * z1 + m.9, m.1 * x1 + m.4 * y1 + m.7 * z1 + m.10,
                        m.2 * x1 + m.5 * y1 + m.8 * z1 + m.11
                    )
                    (x2, y2, z2) = (
                        m.0 * x2 + m.3 * y2 + m.6 * z2 + m.9, m.1 * x2 + m.4 * y2 + m.7 * z2 + m.10,
                        m.2 * x2 + m.5 * y2 + m.8 * z2 + m.11
                    )
                    let (ux, uy, uz) = (x1 - x0, y1 - y0, z1 - z0)
                    let (vx, vy, vz) = (x2 - x0, y2 - y0, z2 - z0)
                    var (nx, ny, nz) = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
                    let length = (nx * nx + ny * ny + nz * nz).squareRoot()
                    if length > 0 {
                        (nx, ny, nz) = (nx / length, ny / length, nz / length)
                    }
                    for (x, y, z) in [(x0, y0, z0), (x1, y1, z1), (x2, y2, z2)] {
                        vertices[output] = x
                        vertices[output + 1] = y
                        vertices[output + 2] = z
                        vertices[output + 3] = nx
                        vertices[output + 4] = ny
                        vertices[output + 5] = nz
                        vertices[output + 6] = r
                        vertices[output + 7] = g
                        vertices[output + 8] = b
                        vertices[output + 9] = alpha
                        output += Self.floatsPerVertex
                    }
                }
            }
            initializedCount = triangleCount * 3 * Self.floatsPerVertex
        }
        vertices += added
    }
}
