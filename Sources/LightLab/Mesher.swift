import VectorMath

/// Triangles to draw: each vertex five 32-bit words, its position in
/// meters as three floats, its normal as four signed bytes, and its material
/// and ambient occlusion, from 0, darkest, to 3, as four unsigned bytes.
struct VoxelMesh {
    static let wordsPerVertex = 5

    var vertices: [UInt32] = []
    var indices: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }

    static func packNormal(_ normal: Vector3<Float>) -> UInt32 {
        func byte(_ value: Float) -> UInt32 {
            UInt32(UInt8(bitPattern: Int8((value * 127).rounded())))
        }
        return byte(normal.x) | byte(normal.y) << 8 | byte(normal.z) << 16
    }

    mutating func appendVertex(position: Vector3<Float>, normal: UInt32, material: UInt8, occlusion: Int) {
        vertices += [
            position.x.bitPattern, position.y.bitPattern, position.z.bitPattern, normal,
            UInt32(material) | UInt32(occlusion) << 8,
        ]
    }
}

/// Meshes a voxel grid into opaque and glass triangles, merging faces of one
/// material and even shading into rectangles.
enum Mesher {
    /// How light treats each voxel: 0 air, 1 opaque, 2 glass.
    private static func opacity(of grid: VoxelGrid) -> [UInt8] {
        grid.data.map { material in
            material == Materials.air ? 0 : Materials.isGlass(material) ? 2 : 1
        }
    }

    /// Meshes `grid`, scaled by `scale` meters a voxel.
    static func mesh(_ grid: VoxelGrid, scale: Float = 1 / Float(voxelsPerMeter)) -> (
        opaque: VoxelMesh, glass: VoxelMesh
    ) {
        var opaque = VoxelMesh()
        var glass = VoxelMesh()
        let kinds = opacity(of: grid)
        let extents = [grid.width, grid.height, grid.depth]
        let strides = [1, grid.width * grid.depth, grid.width]
        let maxPlane = extents.max()!
        // Each cell of a slice: 0 for no face, or the material, its
        // occlusion at four corners and a flag.
        var mask = [UInt32](repeating: 0, count: maxPlane * maxPlane)

        kinds.withUnsafeBufferPointer { kinds in
            grid.data.withUnsafeBufferPointer { data in
                // The kind of voxel at a point: below the grid is solid, and
                // around it air.
                func kind(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
                    if y < 0 { return 1 }
                    guard x >= 0, x < grid.width, y < grid.height, z >= 0, z < grid.depth else { return 0 }
                    return kinds[(y * grid.depth + z) * grid.width + x]
                }

                @inline(__always)
                func set(_ point: inout (Int, Int, Int), _ axis: Int, _ value: Int) {
                    switch axis {
                    case 0: point.0 = value
                    case 1: point.1 = value
                    default: point.2 = value
                    }
                }
                @inline(__always)
                func add(_ point: inout (Int, Int, Int), _ axis: Int, _ value: Int) {
                    switch axis {
                    case 0: point.0 += value
                    case 1: point.1 += value
                    default: point.2 += value
                    }
                }

                for axis in 0..<3 {
                    let uAxis = (axis + 1) % 3
                    let vAxis = (axis + 2) % 3
                    let (uCount, vCount) = (extents[uAxis], extents[vAxis])
                    let (stride, uStride, vStride) = (strides[axis], strides[uAxis], strides[vAxis])
                    for slice in 0..<extents[axis] {
                        for direction in [1, -1] {
                            let neighbor = slice + direction
                            if axis == 1 && neighbor < 0 { continue }
                            var any = false
                            for v in 0..<vCount {
                                for u in 0..<uCount {
                                    let i = slice * stride + u * uStride + v * vStride
                                    let own = kinds[i]
                                    var key: UInt32 = 0
                                    if own != 0 {
                                        // The voxel the face looks onto.
                                        var point = (0, 0, 0)
                                        set(&point, axis, neighbor)
                                        set(&point, uAxis, u)
                                        set(&point, vAxis, v)
                                        let other = kind(point.0, point.1, point.2)
                                        // Opaque faces show beside air and glass;
                                        // glass ones beside air alone.
                                        let shows = own == 1 ? other != 1 : other == 0
                                        if shows {
                                            // Occlusion from the opaque voxels around
                                            // the corners, in the layer beside the face.
                                            func solid(_ a: Int, _ b: Int) -> Int {
                                                var p = point
                                                add(&p, uAxis, a)
                                                add(&p, vAxis, b)
                                                return kind(p.0, p.1, p.2) == 1 ? 1 : 0
                                            }
                                            let (left, right, below, above) = (solid(-1, 0), solid(1, 0), solid(0, -1), solid(0, 1))
                                            func level(_ side1: Int, _ side2: Int, _ diagonal: Int) -> UInt32 {
                                                UInt32(side1 == 1 && side2 == 1 ? 0 : 3 - (side1 + side2 + diagonal))
                                            }
                                            let occlusion =
                                                level(left, below, solid(-1, -1)) << 8
                                                | level(right, below, solid(1, -1)) << 10
                                                | level(right, above, solid(1, 1)) << 12
                                                | level(left, above, solid(-1, 1)) << 14
                                            key = UInt32(data[i]) | occlusion | 1 << 16
                                            any = true
                                        }
                                    }
                                    mask[v * uCount + u] = key
                                }
                            }
                            guard any else { continue }

                            let plane = Float(direction > 0 ? slice + 1 : slice)
                            var normal = Vector3<Float>.zero
                            normal[axis] = Float(direction)
                            let packedNormal = VoxelMesh.packNormal(normal)
                            for v in 0..<vCount {
                                var u = 0
                                while u < uCount {
                                    let key = mask[v * uCount + u]
                                    guard key != 0 else {
                                        u += 1
                                        continue
                                    }
                                    let levels: [Int] = (0..<4).map { (corner: Int) -> Int in
                                        let shift = UInt32(8 + corner * 2)
                                        return Int((key >> shift) & 3)
                                    }
                                    let even = levels.allSatisfy { $0 == levels[0] }
                                    var width = 1
                                    var rows = 1
                                    if even {
                                        while u + width < uCount && mask[v * uCount + u + width] == key {
                                            width += 1
                                        }
                                        grow: while v + rows < vCount {
                                            for k in 0..<width where mask[(v + rows) * uCount + u + k] != key {
                                                break grow
                                            }
                                            rows += 1
                                        }
                                    }
                                    for row in 0..<rows {
                                        for k in 0..<width {
                                            mask[(v + row) * uCount + u + k] = 0
                                        }
                                    }

                                    let material = UInt8(key & 0xff)
                                    let isGlass = Materials.isGlass(material)
                                    let corners = [(u, v), (u + width, v), (u + width, v + rows), (u, v + rows)]
                                    let first = UInt32((isGlass ? glass : opaque).vertices.count / VoxelMesh.wordsPerVertex)
                                    for (corner, (cu, cv)) in corners.enumerated() {
                                        var position = Vector3<Float>.zero
                                        position[axis] = plane * scale
                                        position[uAxis] = Float(cu) * scale
                                        position[vAxis] = Float(cv) * scale
                                        if isGlass {
                                            glass.appendVertex(
                                                position: position, normal: packedNormal, material: material,
                                                occlusion: levels[corner])
                                        } else {
                                            opaque.appendVertex(
                                                position: position, normal: packedNormal, material: material,
                                                occlusion: levels[corner])
                                        }
                                    }
                                    // Counterclockwise from outside, split along the
                                    // diagonal that keeps the shading even.
                                    let flip = levels[0] + levels[2] < levels[1] + levels[3]
                                    let quad: [UInt32] =
                                        flip ? [1, 2, 3, 1, 3, 0] : [0, 1, 2, 0, 2, 3]
                                    let ordered = direction > 0 ? quad : [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
                                    if isGlass {
                                        glass.indices += ordered.map { first + $0 }
                                    } else {
                                        opaque.indices += ordered.map { first + $0 }
                                    }
                                    u += width
                                }
                            }
                        }
                    }
                }
            }
        }
        return (opaque, glass)
    }
}
