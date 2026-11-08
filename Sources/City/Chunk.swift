/// A column of the world 32 m square and as tall as what stands in it.
struct ChunkCoordinate: Hashable {
    var x: Int
    var z: Int

    static let size = 32
}

/// A chunk's voxels, with a border a voxel wide around its sides, so that
/// its faces can be culled against its neighbors without them.
struct ChunkVoxels {
    static let paddedSize = ChunkCoordinate.size + 2

    let coordinate: ChunkCoordinate
    /// How many voxels tall it is, from y 0, the ground.
    let height: Int
    /// The palette index of each voxel, x fastest, then z, then y.
    var data: [UInt8]

    @inline(__always)
    static func index(x: Int, y: Int, z: Int) -> Int {
        (y * paddedSize + z) * paddedSize + x
    }

    /// Generates the chunk at `coordinate` from the city's layout.
    static func generate(_ coordinate: ChunkCoordinate) -> ChunkVoxels {
        let size = paddedSize
        let originX = coordinate.x * ChunkCoordinate.size - 1
        let originZ = coordinate.z * ChunkCoordinate.size - 1
        let region = CityLayout.Rect(x0: originX, z0: originZ, x1: originX + size, z1: originZ + size)

        var plans: [CityLayout.BlockPlan] = []
        for i in CityLayout.blockIndices(from: region.x0, to: region.x1) {
            for j in CityLayout.blockIndices(from: region.z0, to: region.z1) {
                let rect = CityLayout.blockRect(i, j)
                if !rect.isEmpty && rect.intersects(region) {
                    plans.append(CityLayout.blockPlan(i, j))
                }
            }
        }
        let buildings = plans.flatMap(\.buildings).filter { $0.bounds.intersects(region) }
        let trees = (plans.flatMap(\.trees) + CityLayout.streetTrees(in: region)).filter { $0.bounds.intersects(region) }
        let top = max(buildings.map(\.top).max() ?? 0, trees.map(\.top).max() ?? 0)
        let height = top + 1

        var data = [UInt8](repeating: Palette.air, count: size * size * height)
        // The ground, y 0.
        for z in 0..<size {
            for x in 0..<size {
                data[index(x: x, y: 0, z: z)] =
                    CityLayout.streetSurface(x: originX + x, z: originZ + z) ?? Palette.plaza
            }
        }
        for plan in plans {
            for (rect, color) in plan.grounds {
                let clipped = rect.intersection(region)
                guard !clipped.isEmpty else { continue }
                for z in clipped.z0..<clipped.z1 {
                    for x in clipped.x0..<clipped.x1 {
                        data[index(x: x - originX, y: 0, z: z - originZ)] = color
                    }
                }
            }
        }
        for building in buildings {
            let clipped = building.bounds.intersection(region)
            for y in 1...max(building.top, 1) {
                for z in clipped.z0..<clipped.z1 {
                    for x in clipped.x0..<clipped.x1 {
                        let voxel = building.voxel(x: x, y: y, z: z)
                        if voxel != Palette.air {
                            data[index(x: x - originX, y: y, z: z - originZ)] = voxel
                        }
                    }
                }
            }
        }
        for tree in trees {
            let clipped = tree.bounds.intersection(region)
            for y in 1...tree.top {
                for z in clipped.z0..<clipped.z1 {
                    for x in clipped.x0..<clipped.x1 {
                        let i = index(x: x - originX, y: y, z: z - originZ)
                        let voxel = tree.voxel(x: x, y: y, z: z)
                        if voxel != Palette.air && data[i] == Palette.air {
                            data[i] = voxel
                        }
                    }
                }
            }
        }
        return ChunkVoxels(coordinate: coordinate, height: height, data: data)
    }
}

/// A chunk's voxels as cells to mesh: 1 m voxels near the camera, or, as a
/// level of detail farther away, cells `cellSize` meters square.
///
/// A coarse grid keeps the ground a layer 1 m thick, under layers of cells
/// `cellSize` meters tall, so that the ground stays level with the finer
/// chunks around it. A cell is solid where at least half of it is, colored as
/// most of its surface is on its sides and as most of its top is from above.
/// Its sides are not culled against the chunks around it, which keeps finer
/// chunks from showing holes beside it.
struct MeshGrid {
    /// How many meters across a cell is: 1, 2 or 4.
    let cellSize: Int
    /// How many cells a side of the chunk is.
    let size: Int
    /// How many layers of cells it is, from the ground up.
    let layers: Int
    /// The colors of cells' sides and of their tops, with a border a cell
    /// wide around the sides, x fastest, then z, then the layer.
    var side: [UInt8]
    var top: [UInt8]

    var paddedSize: Int { size + 2 }

    /// The height in meters of the bottom of `layer`.
    func layerBottom(_ layer: Int) -> Int {
        cellSize == 1 || layer == 0 ? layer : 1 + (layer - 1) * cellSize
    }

    /// The height in meters of the top of the highest layer.
    var topHeight: Int { layerBottom(layers) }

    /// `voxels` at `cellSize` meters a cell.
    init(_ voxels: ChunkVoxels, cellSize: Int) {
        self.cellSize = cellSize
        if cellSize == 1 {
            size = ChunkCoordinate.size
            layers = voxels.height
            side = voxels.data
            top = voxels.data
            return
        }
        let size = ChunkCoordinate.size / cellSize
        let layers = 1 + (voxels.height - 1 + cellSize - 1) / cellSize
        let padded = size + 2
        let source = ChunkVoxels.paddedSize
        var side = [UInt8](repeating: Palette.air, count: padded * padded * layers)
        var top = side
        var sideCounts = [Int](repeating: 0, count: Palette.colors.count)
        var topCounts = sideCounts

        func majority(_ counts: inout [Int]) -> UInt8 {
            var best = 0
            for index in 1..<counts.count where counts[index] > counts[best] {
                best = index
            }
            for index in counts.indices {
                counts[index] = 0
            }
            return UInt8(best)
        }

        voxels.data.withUnsafeBufferPointer { data in
            for cz in 0..<size {
                for cx in 0..<size {
                    let x0 = 1 + cx * cellSize
                    let z0 = 1 + cz * cellSize
                    let cell = (cz + 1) * padded + cx + 1
                    // The ground, from y 0 alone.
                    for z in z0..<(z0 + cellSize) {
                        for x in x0..<(x0 + cellSize) {
                            sideCounts[Int(data[ChunkVoxels.index(x: x, y: 0, z: z)])] += 1
                        }
                    }
                    let ground = majority(&sideCounts)
                    side[cell] = ground
                    top[cell] = ground

                    for layer in 1..<layers {
                        let y0 = 1 + (layer - 1) * cellSize
                        let y1 = min(y0 + cellSize, voxels.height)
                        var solid = 0
                        var surface = 0
                        for z in z0..<(z0 + cellSize) {
                            for x in x0..<(x0 + cellSize) {
                                var highest = Palette.air
                                for y in y0..<y1 {
                                    let i = ChunkVoxels.index(x: x, y: y, z: z)
                                    let color = data[i]
                                    guard color != Palette.air else { continue }
                                    solid += 1
                                    highest = color
                                    // Inside walls, only voxels beside air
                                    // count for the color of the sides.
                                    let isSurface =
                                        data[i - 1] == Palette.air || data[i + 1] == Palette.air
                                        || data[i - source] == Palette.air || data[i + source] == Palette.air
                                    if isSurface {
                                        sideCounts[Int(color)] += 1
                                        surface += 1
                                    }
                                }
                                if highest != Palette.air {
                                    topCounts[Int(highest)] += 1
                                }
                            }
                        }
                        let index = layer * padded * padded + cell
                        if solid * 2 >= cellSize * cellSize * cellSize {
                            if surface == 0 {
                                // A cell inside a building: its sides are
                                // hidden, so its top will do.
                                side[index] = majority(&topCounts)
                                top[index] = side[index]
                                for i in sideCounts.indices { sideCounts[i] = 0 }
                            } else {
                                side[index] = majority(&sideCounts)
                                top[index] = majority(&topCounts)
                            }
                        } else {
                            for i in sideCounts.indices {
                                sideCounts[i] = 0
                                topCounts[i] = 0
                            }
                        }
                    }
                }
            }
        }
        self.size = size
        self.layers = layers
        self.side = side
        self.top = top
    }
}

/// Triangles of a chunk's visible faces, relative to the chunk's corner.
///
/// Each vertex is four 32-bit words: x, y and z as floats, then the color as
/// RGBA bytes, with the face's direction, from 0 to 5, in place of alpha.
struct ChunkMesh {
    static let wordsPerVertex = 4

    var vertices: [UInt32] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    /// Meshes `grid`, merging adjacent faces of one color and direction into
    /// rectangles (greedy meshing).
    init(_ grid: MeshGrid) {
        let size = grid.size
        let padded = grid.paddedSize
        let height = grid.layers
        // Axis 0 is x, 1 is y and 2 is z, and the axes of each slice are the
        // next two in turn, so that u × v points along the axis.
        let extents = [size, height, size]
        let strides = [1, padded * padded, padded]
        // Where local (0, 0, 0) is in the padded data.
        let base = padded + 1
        let scale = Float(grid.cellSize)
        // The height in meters of each layer boundary.
        let heights = (0...height).map { Float(grid.layerBottom($0)) }
        var vertices: [UInt32] = []
        var indices: [UInt32] = []
        var mask = [UInt8](repeating: 0, count: max(size, height) * max(size, height))

        grid.side.withUnsafeBufferPointer { side in
            grid.top.withUnsafeBufferPointer { top in
                for axis in 0..<3 {
                    let uAxis = (axis + 1) % 3
                    let vAxis = (axis + 2) % 3
                    let (uCount, vCount) = (extents[uAxis], extents[vAxis])
                    let (stride, uStride, vStride) = (strides[axis], strides[uAxis], strides[vAxis])
                    for slice in 0..<extents[axis] {
                        for direction in [1, -1] {
                            // The ground's underside is never seen; above the
                            // chunk is air.
                            let neighborSlice = slice + direction
                            if axis == 1 && neighborSlice < 0 { continue }
                            let neighborIsAir = axis == 1 && neighborSlice >= height
                            let colors = axis == 1 && direction > 0 ? top : side

                            var any = false
                            for v in 0..<vCount {
                                for u in 0..<uCount {
                                    let i = base + slice * stride + u * uStride + v * vStride
                                    let color = colors[i]
                                    var visible = color != Palette.air
                                    if visible && !neighborIsAir {
                                        visible = side[i + direction * stride] == Palette.air
                                    }
                                    mask[v * uCount + u] = visible ? color : 0
                                    any = any || visible
                                }
                            }
                            guard any else { continue }

                            let plane = direction > 0 ? slice + 1 : slice
                            let face = UInt32(axis * 2 + (direction > 0 ? 0 : 1))
                            for v in 0..<vCount {
                                var u = 0
                                while u < uCount {
                                    let color = mask[v * uCount + u]
                                    guard color != 0 else {
                                        u += 1
                                        continue
                                    }
                                    var width = 1
                                    while u + width < uCount && mask[v * uCount + u + width] == color {
                                        width += 1
                                    }
                                    var rows = 1
                                    grow: while v + rows < vCount {
                                        for k in 0..<width where mask[(v + rows) * uCount + u + k] != color {
                                            break grow
                                        }
                                        rows += 1
                                    }
                                    for row in 0..<rows {
                                        for k in 0..<width {
                                            mask[(v + row) * uCount + u + k] = 0
                                        }
                                    }

                                    let first = UInt32(vertices.count / Self.wordsPerVertex)
                                    let packed = Palette.rgba[Int(color)] | face << 24
                                    let corners = [(u, v), (u + width, v), (u + width, v + rows), (u, v + rows)]
                                    for (cu, cv) in corners {
                                        // Cells to meters: across by the cell
                                        // size, up by the layers' heights.
                                        let position: (Float, Float, Float)
                                        switch axis {
                                        case 0: position = (Float(plane) * scale, heights[cu], Float(cv) * scale)
                                        case 1: position = (Float(cv) * scale, heights[plane], Float(cu) * scale)
                                        default: position = (Float(cu) * scale, heights[cv], Float(plane) * scale)
                                        }
                                        vertices += [
                                            position.0.bitPattern, position.1.bitPattern, position.2.bitPattern,
                                            packed,
                                        ]
                                    }
                                    // Counterclockwise from outside.
                                    indices +=
                                        direction > 0
                                        ? [first, first + 1, first + 2, first, first + 2, first + 3]
                                        : [first, first + 2, first + 1, first, first + 3, first + 2]
                                    u += width
                                }
                            }
                        }
                    }
                }
            }
        }
        self.vertices = vertices
        self.indices = indices
    }
}
