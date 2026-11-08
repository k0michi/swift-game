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

    /// Meshes `voxels`, merging adjacent faces of one color and direction
    /// into rectangles (greedy meshing).
    init(_ voxels: ChunkVoxels) {
        let size = ChunkCoordinate.size
        let padded = ChunkVoxels.paddedSize
        let height = voxels.height
        // Axis 0 is x, 1 is y and 2 is z, and the axes of each slice are the
        // next two in turn, so that u × v points along the axis.
        let extents = [size, height, size]
        let strides = [1, padded * padded, padded]
        // Where local (0, 0, 0) is in the padded data.
        let base = ChunkVoxels.index(x: 1, y: 0, z: 1)
        var vertices: [UInt32] = []
        var indices: [UInt32] = []
        var mask = [UInt8](repeating: 0, count: max(size, height) * max(size, height))

        voxels.data.withUnsafeBufferPointer { data in
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

                        var any = false
                        for v in 0..<vCount {
                            for u in 0..<uCount {
                                let i = base + slice * stride + u * uStride + v * vStride
                                let color = data[i]
                                var visible = color != Palette.air
                                if visible && !neighborIsAir {
                                    visible = data[i + direction * stride] == Palette.air
                                }
                                mask[v * uCount + u] = visible ? color : 0
                                any = any || visible
                            }
                        }
                        guard any else { continue }

                        let plane = Float(direction > 0 ? slice + 1 : slice)
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
                                    var position: (Float, Float, Float) = (0, 0, 0)
                                    switch axis {
                                    case 0: position = (plane, Float(cu), Float(cv))
                                    case 1: position = (Float(cv), plane, Float(cu))
                                    default: position = (Float(cu), Float(cv), plane)
                                    }
                                    vertices += [
                                        position.0.bitPattern, position.1.bitPattern, position.2.bitPattern, packed,
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
        self.vertices = vertices
        self.indices = indices
    }
}
