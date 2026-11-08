/// A world of voxels that keeps memory only for the parts with something to
/// tell apart: sections of a single material take no more than a tag.
struct SparseVoxels: Sendable {
    /// How many voxels a section is along each axis.
    static let sectionSize = 32

    private enum Section: Sendable {
        case uniform(UInt8)
        /// Materials, x fastest, then z, then y.
        case dense([UInt8])
    }

    let width: Int
    let height: Int
    let depth: Int
    private let sectionsX: Int
    private let sectionsY: Int
    private let sectionsZ: Int
    private var sections: [Section]

    /// How many sections hold more than one material, and how many there are.
    var denseCount: Int {
        sections.reduce(0) { count, section in
            if case .dense = section { return count + 1 }
            return count
        }
    }
    var sectionCount: Int { sections.count }
    /// The bytes the dense sections take.
    var denseBytes: Int { denseCount * Self.sectionSize * Self.sectionSize * Self.sectionSize }

    /// `tiles` by `tiles` copies of `tile`, whose size is a whole number of
    /// sections. Each dense section has memory of its own, as those of a
    /// world without repeats would.
    @MainActor
    init(tile: VoxelGrid, tiles: Int) async {
        var breather = Breather()
        let size = Self.sectionSize
        precondition(tile.width % size == 0 && tile.height % size == 0 && tile.depth % size == 0)
        width = tile.width * tiles
        height = tile.height
        depth = tile.depth * tiles
        sectionsX = width / size
        sectionsY = height / size
        sectionsZ = depth / size
        var sections: [Section] = []
        sections.reserveCapacity(sectionsX * sectionsY * sectionsZ)
        for sy in 0..<sectionsY {
            for sz in 0..<sectionsZ {
                await breather.breathe()
                for sx in 0..<sectionsX {
                    let originX = sx * size % tile.width
                    let originZ = sz * size % tile.depth
                    let first = tile.data[tile.index(originX, sy * size, originZ)]
                    var isUniform = true
                    var voxels = [UInt8](repeating: first, count: size * size * size)
                    var output = 0
                    for y in 0..<size {
                        for z in 0..<size {
                            let row = tile.index(originX, sy * size + y, originZ + z)
                            for x in 0..<size {
                                let voxel = tile.data[row + x]
                                voxels[output] = voxel
                                output += 1
                                if voxel != first { isUniform = false }
                            }
                        }
                    }
                    sections.append(isUniform ? .uniform(first) : .dense(voxels))
                }
            }
        }
        self.sections = sections
    }

    /// A world of air, of a size in voxels, each a whole number of sections.
    init(width: Int, height: Int, depth: Int) {
        let size = Self.sectionSize
        precondition(width % size == 0 && height % size == 0 && depth % size == 0)
        self.width = width
        self.height = height
        self.depth = depth
        sectionsX = width / size
        sectionsY = height / size
        sectionsZ = depth / size
        sections = Array(repeating: .uniform(Materials.air), count: sectionsX * sectionsY * sectionsZ)
    }

    /// Sets the voxels of a column of sections from `grid`, whose corner is
    /// at voxel (`originX`, 0, `originZ`), and which is a whole number of
    /// sections. Sections past the world's edges are left out.
    mutating func set(_ grid: VoxelGrid, originX: Int, originZ: Int) {
        let size = Self.sectionSize
        for sy in 0..<sectionsY {
            for offsetZ in 0..<(grid.depth / size) {
                for offsetX in 0..<(grid.width / size) {
                    let sx = originX / size + offsetX
                    let sz = originZ / size + offsetZ
                    guard sx < sectionsX, sz < sectionsZ else { continue }
                    let first = grid.data[grid.index(offsetX * size, sy * size, offsetZ * size)]
                    var isUniform = true
                    var voxels = [UInt8](repeating: first, count: size * size * size)
                    var output = 0
                    for y in 0..<size {
                        for z in 0..<size {
                            let row = grid.index(offsetX * size, sy * size + y, offsetZ * size + z)
                            for x in 0..<size {
                                let voxel = grid.data[row + x]
                                voxels[output] = voxel
                                output += 1
                                if voxel != first { isUniform = false }
                            }
                        }
                    }
                    sections[(sy * sectionsZ + sz) * sectionsX + sx] = isUniform ? .uniform(first) : .dense(voxels)
                }
            }
        }
    }

    /// A world with nothing in it.
    init() {
        width = 0
        height = 0
        depth = 0
        sectionsX = 0
        sectionsY = 0
        sectionsZ = 0
        sections = []
    }

    /// How many layers of voxels make up one slice of `occupancySlice`.
    static var sliceHeight: Int { sectionSize }

    /// How many slices the world is, from the ground up.
    var sliceCount: Int { sectionsY }

    private static let kinds: [UInt8] = Materials.table.indices.map { index in
        index == Int(Materials.air) ? 0 : Materials.isGlass(UInt8(index)) ? 2 : 1
    }

    /// What light needs to know of a slice of the columns over `x` and `z`,
    /// `sliceHeight` voxels tall: 0 air, 1 opaque, 2 glass, x fastest, then z,
    /// then y. Past the edges of the world there is air.
    func occupancySlice(x: Range<Int>, z: Range<Int>, slice: Int) -> [UInt8] {
        let size = Self.sectionSize
        let (rowsWide, rowsDeep) = (x.count, z.count)
        var output = [UInt8](repeating: 0, count: rowsWide * rowsDeep * size)
        func section(_ value: Int) -> Int { value >= 0 ? value / size : -((-value + size - 1) / size) }
        Self.kinds.withUnsafeBufferPointer { kinds in
            output.withUnsafeMutableBufferPointer { output in
                for sz in stride(from: max(section(z.lowerBound), 0), through: min(section(z.upperBound - 1), sectionsZ - 1), by: 1) {
                    for sx in stride(from: max(section(x.lowerBound), 0), through: min(section(x.upperBound - 1), sectionsX - 1), by: 1) {
                        let columnsX = max(sx * size, x.lowerBound)..<min((sx + 1) * size, x.upperBound)
                        let columnsZ = max(sz * size, z.lowerBound)..<min((sz + 1) * size, z.upperBound)
                        switch sections[(slice * sectionsZ + sz) * sectionsX + sx] {
                        case .uniform(let material):
                            let kind = kinds[Int(material)]
                            guard kind != 0 else { continue }
                            for y in 0..<size {
                                for worldZ in columnsZ {
                                    let start = (y * rowsDeep + worldZ - z.lowerBound) * rowsWide + columnsX.lowerBound - x.lowerBound
                                    for offset in 0..<columnsX.count {
                                        output[start + offset] = kind
                                    }
                                }
                            }
                        case .dense(let voxels):
                            voxels.withUnsafeBufferPointer { voxels in
                                for y in 0..<size {
                                    for worldZ in columnsZ {
                                        let start = (y * rowsDeep + worldZ - z.lowerBound) * rowsWide + columnsX.lowerBound - x.lowerBound
                                        let row = (y * size + worldZ - sz * size) * size + columnsX.lowerBound - sx * size
                                        for offset in 0..<columnsX.count {
                                            output[start + offset] = kinds[Int(voxels[row + offset])]
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return output
    }

    /// The material at a voxel: air outside the world, but for below it,
    /// which is solid.
    subscript(x: Int, y: Int, z: Int) -> UInt8 {
        if y < 0 { return Materials.soil }
        guard x >= 0, x < width, y < height, z >= 0, z < depth else { return Materials.air }
        let size = Self.sectionSize
        let index = ((y / size * sectionsZ + z / size) * sectionsX) + x / size
        switch sections[index] {
        case .uniform(let material):
            return material
        case .dense(let voxels):
            return voxels[((y % size * size + z % size) * size) + x % size]
        }
    }

    /// The voxels of columns over `x` and `z`, which may reach past the edges
    /// of the world, where there is air.
    func region(x: Range<Int>, z: Range<Int>) -> VoxelGrid {
        var grid = VoxelGrid(width: x.count, height: height, depth: z.count)
        let size = Self.sectionSize
        let (rowsWide, rowsDeep) = (x.count, z.count)
        func floorDivide(_ a: Int) -> Int { a >= 0 ? a / size : -((-a + size - 1) / size) }
        grid.data.withUnsafeMutableBufferPointer { output in
            for sy in 0..<sectionsY {
                for sz in stride(from: max(floorDivide(z.lowerBound), 0), through: min(floorDivide(z.upperBound - 1), sectionsZ - 1), by: 1) {
                    for sx in stride(from: max(floorDivide(x.lowerBound), 0), through: min(floorDivide(x.upperBound - 1), sectionsX - 1), by: 1) {
                        let section = sections[(sy * sectionsZ + sz) * sectionsX + sx]
                        if case .uniform(Materials.air) = section { continue }
                        let columnsX = max(sx * size, x.lowerBound)..<min((sx + 1) * size, x.upperBound)
                        let columnsZ = max(sz * size, z.lowerBound)..<min((sz + 1) * size, z.upperBound)
                        for y in 0..<size {
                            for worldZ in columnsZ {
                                let start =
                                    ((sy * size + y) * rowsDeep + (worldZ - z.lowerBound)) * rowsWide
                                    + (columnsX.lowerBound - x.lowerBound)
                                switch section {
                                case .uniform(let material):
                                    for offset in 0..<columnsX.count {
                                        output[start + offset] = material
                                    }
                                case .dense(let voxels):
                                    let row =
                                        (y * size + (worldZ - sz * size)) * size + (columnsX.lowerBound - sx * size)
                                    voxels.withUnsafeBufferPointer { voxels in
                                        for offset in 0..<columnsX.count {
                                            output[start + offset] = voxels[row + offset]
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return grid
    }
}
