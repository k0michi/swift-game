import VectorMath

/// A solid shape of flat triangles, in its own space, wound counterclockwise
/// as seen from outside.
public struct Mesh: Sendable {
    /// Each three positions are a triangle.
    public let positions: [Vector3<Float>]

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
        let positions = mesh.positions.map { (transform * Vector4($0, 1)).xyz }
        for start in stride(from: 0, to: positions.count, by: 3) {
            let (a, b, c) = (positions[start], positions[start + 1], positions[start + 2])
            let normal = normalize(cross(b - a, c - a))
            for position in [a, b, c] {
                vertices += [position.x, position.y, position.z, normal.x, normal.y, normal.z]
                vertices += [color.r, color.g, color.b, color.a]
            }
        }
    }
}
