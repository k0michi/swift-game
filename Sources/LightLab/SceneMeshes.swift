import VectorMath

/// The triangles of a column of the scene, and the box they fill.
struct SceneChunk {
    /// How many voxels wide and deep a chunk is: 16 m.
    static let size = 128

    var minimum: Vector3<Float>
    var maximum: Vector3<Float>
    var opaque: VoxelMesh
    var glass: VoxelMesh
}

/// The meshing of a chunk, a few layers at a time, so that it can be spread
/// over frames.
struct ChunkMeshing {
    private let xs: Range<Int>
    private let zs: Range<Int>
    private let grid: VoxelGrid
    private let kinds: [UInt8]
    private var nextSlice = 0
    private var opaque = VoxelMesh()
    private var glass = VoxelMesh()

    private static let sliceHeight = SparseVoxels.sliceHeight

    init(x: Int, z: Int, voxels: SparseVoxels) {
        xs = x..<min(x + SceneChunk.size, voxels.width)
        zs = z..<min(z + SceneChunk.size, voxels.depth)
        // With a border a voxel wide, to cull and shade the faces at the
        // chunk's edges.
        grid = voxels.region(x: (x - 1)..<(xs.upperBound + 1), z: (z - 1)..<(zs.upperBound + 1))
        kinds = Mesher.opacity(of: grid)
    }

    /// Meshes the next layers, and says whether any are left.
    mutating func step() -> Bool {
        let bottom = nextSlice * Self.sliceHeight
        let (sliceOpaque, sliceGlass) = Mesher.mesh(
            grid, kinds: kinds,
            region: (1..<(xs.count + 1), bottom..<min(bottom + Self.sliceHeight, grid.height), 1..<(zs.count + 1)))
        opaque.append(sliceOpaque)
        glass.append(sliceGlass)
        nextSlice += 1
        return nextSlice * Self.sliceHeight < grid.height
    }

    /// The chunk, placed in the world, or nothing if it has no faces.
    func finished() -> SceneChunk? {
        guard !opaque.indices.isEmpty || !glass.indices.isEmpty else { return nil }
        let scale = 1 / Float(voxelsPerMeter)
        let (shiftX, shiftZ) = (Float(xs.lowerBound - 1) * scale, Float(zs.lowerBound - 1) * scale)
        var top: Float = 0
        func placed(_ mesh: VoxelMesh) -> VoxelMesh {
            var mesh = mesh
            for base in stride(from: 0, to: mesh.vertices.count, by: VoxelMesh.wordsPerVertex) {
                mesh.vertices[base] = (Float(bitPattern: mesh.vertices[base]) + shiftX).bitPattern
                mesh.vertices[base + 2] = (Float(bitPattern: mesh.vertices[base + 2]) + shiftZ).bitPattern
                top = max(top, Float(bitPattern: mesh.vertices[base + 1]))
            }
            return mesh
        }
        let placedOpaque = placed(opaque)
        let placedGlass = placed(glass)
        return SceneChunk(
            minimum: Vector3(Float(xs.lowerBound) * scale, 0, Float(zs.lowerBound) * scale),
            maximum: Vector3(Float(xs.upperBound) * scale, top, Float(zs.upperBound) * scale),
            opaque: placedOpaque, glass: placedGlass)
    }
}
