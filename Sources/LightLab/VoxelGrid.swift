/// How many voxels make a meter.
let voxelsPerMeter = 8

/// The voxel index nearest `meters`.
@inline(__always)
func cells(_ meters: Float) -> Int {
    Int((meters * Float(voxelsPerMeter)).rounded())
}

/// A box of voxels the scene is built in, each a material index, x fastest,
/// then z, then y.
struct VoxelGrid {
    let width: Int
    let height: Int
    let depth: Int
    var data: [UInt8]

    init(width: Int, height: Int, depth: Int) {
        self.width = width
        self.height = height
        self.depth = depth
        data = [UInt8](repeating: Materials.air, count: width * height * depth)
    }

    @inline(__always)
    func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
        (y * depth + z) * width + x
    }

    @inline(__always)
    func contains(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height && z >= 0 && z < depth
    }

    /// The material at a voxel: air outside the grid, but for below it,
    /// which is solid.
    @inline(__always)
    subscript(x: Int, y: Int, z: Int) -> UInt8 {
        get {
            if y < 0 { return Materials.soil }
            return contains(x, y, z) ? data[index(x, y, z)] : Materials.air
        }
        set {
            if contains(x, y, z) {
                data[index(x, y, z)] = newValue
            }
        }
    }

    /// Fills voxels from each lower bound up to, but not including, each
    /// upper one.
    mutating func fill(x: Range<Int>, y: Range<Int>, z: Range<Int>, _ material: UInt8) {
        let xs = max(x.lowerBound, 0)..<min(x.upperBound, width)
        let ys = max(y.lowerBound, 0)..<min(y.upperBound, height)
        let zs = max(z.lowerBound, 0)..<min(z.upperBound, depth)
        guard !xs.isEmpty, !ys.isEmpty, !zs.isEmpty else { return }
        for yy in ys {
            for zz in zs {
                let row = index(0, yy, zz)
                for xx in xs {
                    data[row + xx] = material
                }
            }
        }
    }

    /// Fills the box between two corners in meters, each rounded to the
    /// nearest voxel.
    mutating func fill(
        x: ClosedRange<Float>, y: ClosedRange<Float>, z: ClosedRange<Float>, _ material: UInt8
    ) {
        fill(
            x: cells(x.lowerBound)..<cells(x.upperBound), y: cells(y.lowerBound)..<cells(y.upperBound),
            z: cells(z.lowerBound)..<cells(z.upperBound), material)
    }

    /// Whether light stops at a voxel: what is not air or glass.
    @inline(__always)
    func isOpaque(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        let material = self[x, y, z]
        return material != Materials.air && !Materials.isGlass(material)
    }
}
