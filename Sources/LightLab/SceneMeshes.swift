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

    static func build(_ voxels: SparseVoxels) async -> SceneMeshes {
        let chunks = await withTaskGroup(of: SceneChunk?.self) { group in
            for z in stride(from: 0, to: voxels.depth, by: SceneChunk.size) {
                for x in stride(from: 0, to: voxels.width, by: SceneChunk.size) {
                    group.addTask {
                        let xs = x..<min(x + SceneChunk.size, voxels.width)
                        let zs = z..<min(z + SceneChunk.size, voxels.depth)
                        // With a border a voxel wide, to cull and shade the
                        // faces at the chunk's edges.
                        let local = voxels.region(x: (x - 1)..<(xs.upperBound + 1), z: (z - 1)..<(zs.upperBound + 1))
                        let (localOpaque, localGlass) = Mesher.mesh(
                            local, region: (1..<(xs.count + 1), 0..<voxels.height, 1..<(zs.count + 1)))
                        guard !localOpaque.indices.isEmpty || !localGlass.indices.isEmpty else { return nil }
                        let scale = 1 / Float(voxelsPerMeter)
                        let (shiftX, shiftZ) = (Float(x - 1) * scale, Float(z - 1) * scale)
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
                        let opaque = placed(localOpaque)
                        let glass = placed(localGlass)
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
        return SceneMeshes(chunks: chunks)
    }
}
