import VectorMath

/// Keeps the chunks within the draw distance of the focus generated and on
/// the GPU, nearest first and a few a frame, and drops those that fall far
/// behind.
@MainActor
final class ChunkStreamer {
    /// How many chunks from the focus's chunk are drawn.
    let radius: Int
    private let renderer: ChunkRenderer
    /// The chunks that are ready: nil for those with nothing to draw.
    private(set) var chunks: [ChunkCoordinate: GPUChunk?] = [:]
    private(set) var triangleCount = 0
    /// How many chunks within the radius were still missing after the last
    /// update.
    private(set) var pendingCount = 0
    private var triangleCounts: [ChunkCoordinate: Int] = [:]

    init(renderer: ChunkRenderer, radius: Int) {
        self.renderer = renderer
        self.radius = radius
    }

    /// The chunk that holds a point, in meters.
    static func chunk(containing x: Int, _ z: Int) -> ChunkCoordinate {
        ChunkCoordinate(x: floorDivide(x, ChunkCoordinate.size), z: floorDivide(z, ChunkCoordinate.size))
    }

    /// Generates missing chunks around `center`, nearest first, until
    /// `budget` has passed, and drops chunks beyond the radius.
    func update(around center: ChunkCoordinate, budget: Duration) throws {
        let keep = radius + 2
        for coordinate in chunks.keys
        where abs(coordinate.x - center.x) > keep || abs(coordinate.z - center.z) > keep {
            chunks[coordinate] = nil
            triangleCount -= triangleCounts.removeValue(forKey: coordinate) ?? 0
        }

        var missing: [(coordinate: ChunkCoordinate, distance: Int)] = []
        for dz in -radius...radius {
            for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                let coordinate = ChunkCoordinate(x: center.x + dx, z: center.z + dz)
                if chunks[coordinate] == nil {
                    missing.append((coordinate, dx * dx + dz * dz))
                }
            }
        }
        pendingCount = missing.count
        guard !missing.isEmpty else { return }
        missing.sort { $0.distance < $1.distance }

        let clock = ContinuousClock()
        let start = clock.now
        for (coordinate, _) in missing {
            let voxels = ChunkVoxels.generate(coordinate)
            let mesh = ChunkMesh(voxels)
            chunks[coordinate] = .some(try renderer.upload(mesh, height: voxels.height))
            triangleCounts[coordinate] = mesh.triangleCount
            triangleCount += mesh.triangleCount
            pendingCount -= 1
            if clock.now - start > budget {
                break
            }
        }
    }

    /// The chunks to draw through `viewProjection`, which maps positions
    /// relative to `anchor`, each with its corner's offset from the anchor.
    func visibleChunks(anchor: (x: Int, z: Int), viewProjection: Matrix4x4<Float>) -> [(
        chunk: GPUChunk, offset: Vector3<Float>
    )] {
        var visible: [(chunk: GPUChunk, offset: Vector3<Float>)] = []
        let size = Float(ChunkCoordinate.size)
        for (coordinate, chunk) in chunks {
            guard let chunk else { continue }
            let offset = Vector3<Float>(
                Float(coordinate.x * ChunkCoordinate.size - anchor.x), 0,
                Float(coordinate.z * ChunkCoordinate.size - anchor.z))
            // Culls the chunk's box when all its corners are beyond one side
            // of the view.
            var outside = (left: true, right: true, bottom: true, top: true)
            for corner in 0..<8 {
                let point = Vector4<Float>(
                    offset.x + (corner & 1 == 0 ? 0 : size), corner & 2 == 0 ? 0 : Float(chunk.height),
                    offset.z + (corner & 4 == 0 ? 0 : size), 1)
                let clip = viewProjection * point
                outside.left = outside.left && clip.x < -clip.w
                outside.right = outside.right && clip.x > clip.w
                outside.bottom = outside.bottom && clip.y < -clip.w
                outside.top = outside.top && clip.y > clip.w
            }
            if !(outside.left || outside.right || outside.bottom || outside.top) {
                visible.append((chunk, offset))
            }
        }
        return visible
    }
}
