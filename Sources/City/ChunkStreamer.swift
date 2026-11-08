import VectorMath

/// Keeps the chunks within the draw distance of the focus generated and on
/// the GPU, a few a frame, and drops those that fall far behind.
///
/// The camera is orthographic, so a chunk looks as large wherever it is on
/// the screen: what sets how fine to mesh it is how many meters a pixel
/// covers, at the zoom, and whether it is on the screen at all. Chunks in
/// view are meshed as fine as the pixels show; the rest, kept for when the
/// view moves to them, in the coarsest cells.
@MainActor
final class ChunkStreamer {
    /// A chunk on the GPU: nil where it has nothing to draw.
    struct Loaded {
        var chunk: GPUChunk?
        /// The cell size it was meshed at.
        var cellSize: Int
        var triangleCount: Int
        /// How many meters tall it is.
        var height: Int
    }

    /// How many chunks from the focus's chunk are kept.
    let radius: Int
    static let coarsestCellSize = 4
    /// How many pixels a cell may be across on the screen and still be
    /// meshed coarser than 1 m.
    static let pixelsPerCoarseCell: Float = 4
    /// How far past the edges of the screen, as a fraction of its half size,
    /// chunks count as in view, so that panning finds them ready.
    static let viewMargin: Float = 0.25
    /// Past the edges by this much, chunks in view before are not coarsened,
    /// so that panning to and fro does not remesh them.
    static let keepMargin: Float = 1
    /// A height to cull chunks not generated yet against.
    private static let unknownHeight = 120

    private let renderer: ChunkRenderer
    private(set) var chunks: [ChunkCoordinate: Loaded] = [:]
    private(set) var triangleCount = 0
    /// How many chunks within the radius were still missing, or meshed too
    /// coarse for the view, after the last update.
    private(set) var pendingCount = 0

    init(renderer: ChunkRenderer, radius: Int) {
        self.renderer = renderer
        self.radius = radius
    }

    /// The chunk that holds a point, in meters.
    static func chunk(containing x: Int, _ z: Int) -> ChunkCoordinate {
        ChunkCoordinate(x: floorDivide(x, ChunkCoordinate.size), z: floorDivide(z, ChunkCoordinate.size))
    }

    /// The largest cell size, of 1, 2 and 4 m, no more than
    /// `pixelsPerCoarseCell` pixels across at `metersPerPixel`.
    static func cellSize(metersPerPixel: Float) -> Int {
        var size = 1
        while size < coarsestCellSize && Float(size * 2) <= metersPerPixel * pixelsPerCoarseCell {
            size *= 2
        }
        return size
    }

    /// The offset of a chunk's corner from the anchor.
    private static func offset(of coordinate: ChunkCoordinate, anchor: (x: Int, z: Int)) -> Vector3<Float> {
        Vector3(
            Float(coordinate.x * ChunkCoordinate.size - anchor.x), 0,
            Float(coordinate.z * ChunkCoordinate.size - anchor.z))
    }

    /// Whether any of a chunk's box, `height` meters tall, is within the
    /// screen grown by `margin` of its half size on each side.
    private static func isInView(
        offset: Vector3<Float>, height: Int, viewProjection: Matrix4x4<Float>, margin: Float
    ) -> Bool {
        let size = Float(ChunkCoordinate.size)
        let edge = 1 + margin
        var outside = (left: true, right: true, bottom: true, top: true)
        for corner in 0..<8 {
            let point = Vector4<Float>(
                offset.x + (corner & 1 == 0 ? 0 : size), corner & 2 == 0 ? 0 : Float(height),
                offset.z + (corner & 4 == 0 ? 0 : size), 1)
            let clip = viewProjection * point
            outside.left = outside.left && clip.x < -edge * clip.w
            outside.right = outside.right && clip.x > edge * clip.w
            outside.bottom = outside.bottom && clip.y < -edge * clip.w
            outside.top = outside.top && clip.y > edge * clip.w
        }
        return !(outside.left || outside.right || outside.bottom || outside.top)
    }

    /// Generates missing chunks around the anchor and remeshes those whose
    /// detail no longer fits the view, most urgent first, until `budget` has
    /// passed. Drops chunks beyond the radius.
    func update(
        anchor: (x: Int, z: Int), viewProjection: Matrix4x4<Float>, metersPerPixel: Float, budget: Duration
    ) throws {
        let center = Self.chunk(containing: anchor.x, anchor.z)
        let keep = radius + 2
        for (coordinate, loaded) in chunks
        where abs(coordinate.x - center.x) > keep || abs(coordinate.z - center.z) > keep {
            chunks[coordinate] = nil
            triangleCount -= loaded.triangleCount
        }

        let onScreenCellSize = Self.cellSize(metersPerPixel: metersPerPixel)
        // In order: chunks in view that are missing or too coarse; chunks
        // out of view that are missing; and chunks well out of view that are
        // finer than they need be, which only cost memory.
        var work: [[(coordinate: ChunkCoordinate, distance: Int, cellSize: Int)]] = [[], [], []]
        for dz in -radius...radius {
            for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                let coordinate = ChunkCoordinate(x: center.x + dx, z: center.z + dz)
                let distance = dx * dx + dz * dz
                let loaded = chunks[coordinate]
                let offset = Self.offset(of: coordinate, anchor: anchor)
                let height = loaded?.height ?? Self.unknownHeight
                let inView = Self.isInView(
                    offset: offset, height: height, viewProjection: viewProjection, margin: Self.viewMargin)
                if inView {
                    if loaded.map({ $0.cellSize > onScreenCellSize }) ?? true {
                        work[0].append((coordinate, distance, onScreenCellSize))
                    }
                } else if let loaded {
                    if loaded.cellSize < Self.coarsestCellSize
                        && !Self.isInView(
                            offset: offset, height: height, viewProjection: viewProjection, margin: Self.keepMargin)
                    {
                        work[2].append((coordinate, distance, Self.coarsestCellSize))
                    }
                } else {
                    work[1].append((coordinate, distance, Self.coarsestCellSize))
                }
            }
        }
        pendingCount = work[0].count + work[1].count
        guard work.contains(where: { !$0.isEmpty }) else { return }

        let clock = ContinuousClock()
        let start = clock.now
        for tasks in work {
            for (coordinate, _, cellSize) in tasks.sorted(by: { $0.distance < $1.distance }) {
                let voxels = ChunkVoxels.generate(coordinate)
                let grid = MeshGrid(voxels, cellSize: cellSize)
                let mesh = ChunkMesh(grid)
                let previous = chunks[coordinate]
                chunks[coordinate] = Loaded(
                    chunk: try renderer.upload(mesh, height: grid.topHeight), cellSize: cellSize,
                    triangleCount: mesh.triangleCount, height: grid.topHeight)
                triangleCount += mesh.triangleCount - (previous?.triangleCount ?? 0)
                if previous.map({ $0.cellSize > cellSize }) ?? true {
                    pendingCount -= 1
                }
                if clock.now - start > budget {
                    return
                }
            }
        }
    }

    /// The chunks to draw through `viewProjection`, which maps positions
    /// relative to `anchor`, each with its corner's offset from the anchor.
    func visibleChunks(anchor: (x: Int, z: Int), viewProjection: Matrix4x4<Float>) -> [(
        chunk: GPUChunk, offset: Vector3<Float>
    )] {
        var visible: [(chunk: GPUChunk, offset: Vector3<Float>)] = []
        for (coordinate, loaded) in chunks {
            guard let chunk = loaded.chunk else { continue }
            let offset = Self.offset(of: coordinate, anchor: anchor)
            if Self.isInView(offset: offset, height: loaded.height, viewProjection: viewProjection, margin: 0) {
                visible.append((chunk, offset))
            }
        }
        return visible
    }
}
