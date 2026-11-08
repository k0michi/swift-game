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
    private let sections: [Section]

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
    init(tile: VoxelGrid, tiles: Int) {
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
