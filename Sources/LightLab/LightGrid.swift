/// Which lamps reach each square of a grid over the ground, so that a point
/// needs to look only at the lamps of its own square, however many there are
/// elsewhere.
struct LightGrid {
    /// How wide a square is, in meters.
    static let cellSize: Float = 4
    /// How much farther than a lamp's light a square lists it, for the
    /// highlights on glass.
    static let reachFactor: Float = 1.5

    let width: Int
    let depth: Int
    /// For each square, x fastest, where its lamps start in `indices` and
    /// how many there are.
    private(set) var cells: [UInt32]
    /// The lamps of each square, in turn. Never empty.
    private(set) var indices: [UInt32] = []

    /// How many squares cover a scene of a size in meters.
    static func dimensions(sceneWidth: Float, sceneDepth: Float) -> (width: Int, depth: Int) {
        (Int((sceneWidth / cellSize).rounded(.up)), Int((sceneDepth / cellSize).rounded(.up)))
    }

    init(lights: [PointLight], sceneWidth: Float, sceneDepth: Float) {
        (width, depth) = Self.dimensions(sceneWidth: sceneWidth, sceneDepth: sceneDepth)
        var lists = [[UInt32]](repeating: [], count: width * depth)
        for (index, light) in lights.enumerated() {
            let reach = light.radius * Self.reachFactor
            func cell(_ value: Float) -> Int { Int((value / Self.cellSize).rounded(.down)) }
            let x0 = max(cell(light.position.x - reach), 0)
            let x1 = min(cell(light.position.x + reach), width - 1)
            let z0 = max(cell(light.position.z - reach), 0)
            let z1 = min(cell(light.position.z + reach), depth - 1)
            guard x0 <= x1, z0 <= z1 else { continue }
            for z in z0...z1 {
                for x in x0...x1 {
                    lists[z * width + x].append(UInt32(index))
                }
            }
        }
        cells = []
        cells.reserveCapacity(lists.count * 2)
        for list in lists {
            cells += [UInt32(indices.count), UInt32(list.count)]
            indices += list
        }
        if indices.isEmpty {
            indices = [0]
        }
    }
}
