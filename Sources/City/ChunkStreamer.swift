import VectorMath

/// Keeps the chunks within the draw distance of the focus generated and on
/// the GPU, nearest first and a few a frame, in coarser cells farther away,
/// and drops those that fall far behind.
@MainActor
final class ChunkStreamer {
    /// A chunk on the GPU: nil where it has nothing to draw.
    struct Loaded {
        var chunk: GPUChunk?
        /// The cell size it was meshed at.
        var cellSize: Int
        var triangleCount: Int
    }

    /// How many chunks from the focus's chunk are drawn.
    let radius: Int
    /// Up to how many chunks away cells are 1 m, then 2 m; beyond, 4 m.
    let detailRadii: (fine: Int, medium: Int)
    private let renderer: ChunkRenderer
    private(set) var chunks: [ChunkCoordinate: Loaded] = [:]
    private(set) var triangleCount = 0
    /// How many chunks within the radius were still missing, or meshed too
    /// coarse for where they are, after the last update.
    private(set) var pendingCount = 0

    init(renderer: ChunkRenderer, radius: Int) {
        self.renderer = renderer
        self.radius = radius
        detailRadii = (fine: max(radius / 3, 6), medium: max(radius * 2 / 3, 10))
    }

    /// The chunk that holds a point, in meters.
    static func chunk(containing x: Int, _ z: Int) -> ChunkCoordinate {
        ChunkCoordinate(x: floorDivide(x, ChunkCoordinate.size), z: floorDivide(z, ChunkCoordinate.size))
    }

    /// The cell size for a chunk `distanceSquared` chunks squared away.
    private func cellSize(distanceSquared: Int) -> Int {
        distanceSquared <= detailRadii.fine * detailRadii.fine
            ? 1 : distanceSquared <= detailRadii.medium * detailRadii.medium ? 2 : 4
    }

    /// Generates missing chunks around `center`, and remeshes those too
    /// coarse or, with some slack, too fine for where they now are, nearest
    /// first, until `budget` has passed. Drops chunks beyond the radius.
    func update(around center: ChunkCoordinate, budget: Duration) throws {
        let keep = radius + 2
        for (coordinate, loaded) in chunks
        where abs(coordinate.x - center.x) > keep || abs(coordinate.z - center.z) > keep {
            chunks[coordinate] = nil
            triangleCount -= loaded.triangleCount
        }

        // Needed sooner: missing chunks and ones too coarse. Later: ones
        // finer than they need be by a ring, which only cost memory.
        var needed: [(coordinate: ChunkCoordinate, distance: Int, cellSize: Int)] = []
        var coarsenable: [(coordinate: ChunkCoordinate, distance: Int, cellSize: Int)] = []
        for dz in -radius...radius {
            for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                let coordinate = ChunkCoordinate(x: center.x + dx, z: center.z + dz)
                let distance = dx * dx + dz * dz
                let wanted = cellSize(distanceSquared: distance)
                guard let loaded = chunks[coordinate] else {
                    needed.append((coordinate, distance, wanted))
                    continue
                }
                if loaded.cellSize > wanted {
                    needed.append((coordinate, distance, wanted))
                } else if loaded.cellSize < wanted {
                    let near = max(Int(Float(distance).squareRoot()) - 2, 0)
                    if loaded.cellSize < cellSize(distanceSquared: near * near) {
                        coarsenable.append((coordinate, distance, wanted))
                    }
                }
            }
        }
        pendingCount = needed.count
        guard !needed.isEmpty || !coarsenable.isEmpty else { return }
        needed.sort { $0.distance < $1.distance }

        let clock = ContinuousClock()
        let start = clock.now
        for (coordinate, _, cellSize) in needed + coarsenable {
            let voxels = ChunkVoxels.generate(coordinate)
            let grid = MeshGrid(voxels, cellSize: cellSize)
            let mesh = ChunkMesh(grid)
            let loaded = Loaded(
                chunk: try renderer.upload(mesh, height: grid.topHeight), cellSize: cellSize,
                triangleCount: mesh.triangleCount)
            triangleCount += loaded.triangleCount - (chunks[coordinate]?.triangleCount ?? 0)
            if chunks[coordinate].map({ $0.cellSize > cellSize }) ?? true {
                pendingCount -= 1
            }
            chunks[coordinate] = loaded
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
        for (coordinate, loaded) in chunks {
            guard let chunk = loaded.chunk else { continue }
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
