import VectorMath

/// The triangles of a column of the scene, and the box they fill.
struct SceneChunk: Sendable {
    /// How many voxels wide and deep a chunk is: 16 m.
    static let size = 128

    var minimum: Vector3<Float>
    var maximum: Vector3<Float>
    var opaque: VoxelMesh
    var glass: VoxelMesh
}

/// The scene's chunks, meshed side by side.
struct SceneMeshes: Sendable {
    var chunks: [SceneChunk]
    /// How light treats each voxel of the grid: 0 air, 1 opaque, 2 glass.
    var kinds: [UInt8]

    static func build(_ grid: VoxelGrid) async -> SceneMeshes {
        let kinds = Mesher.opacity(of: grid)
        let chunks = await withTaskGroup(of: SceneChunk?.self) { group in
            for z in stride(from: 0, to: grid.depth, by: SceneChunk.size) {
                for x in stride(from: 0, to: grid.width, by: SceneChunk.size) {
                    group.addTask {
                        let xs = x..<min(x + SceneChunk.size, grid.width)
                        let zs = z..<min(z + SceneChunk.size, grid.depth)
                        let (opaque, glass) = Mesher.mesh(grid, kinds: kinds, region: (xs, 0..<grid.height, zs))
                        guard !opaque.indices.isEmpty || !glass.indices.isEmpty else { return nil }
                        let scale = 1 / Float(voxelsPerMeter)
                        var top: Float = 0
                        for mesh in [opaque, glass] {
                            for word in stride(from: 1, to: mesh.vertices.count, by: VoxelMesh.wordsPerVertex) {
                                top = max(top, Float(bitPattern: mesh.vertices[word]))
                            }
                        }
                        return SceneChunk(
                            minimum: Vector3(Float(xs.lowerBound) * scale, 0, Float(zs.lowerBound) * scale),
                            maximum: Vector3(Float(xs.upperBound) * scale, top, Float(zs.upperBound) * scale),
                            opaque: opaque, glass: glass)
                    }
                }
            }
            var chunks: [SceneChunk] = []
            for await chunk in group {
                if let chunk { chunks.append(chunk) }
            }
            return chunks
        }
        return SceneMeshes(chunks: chunks, kinds: kinds)
    }
}
