/// The endless city, laid out from hashes of coordinates, so that any part of
/// it can be generated on its own and always comes out the same.
///
/// A voxel is 1 m across. Streets cross in an irregular grid; the blocks
/// between them are split into lots of any size, and each lot holds a
/// building of any footprint and height, or a garden. A floor is 3 m: a slab
/// band and two rows of windows.
enum CityLayout {
    /// The average distance between streets, in meters.
    static let streetPitch = 76
    static let floorHeight = 3

    // MARK: Streets

    enum Axis {
        /// Streets that span a range of x and run along z.
        case x
        /// Streets that span a range of z and run along x.
        case z

        var other: Axis { self == .x ? .z : .x }
    }

    /// A straight street of every coordinate from `start` up to `end` on its
    /// axis.
    struct Street {
        let index: Int
        let start: Int
        let end: Int
        let isAvenue: Bool

        var width: Int { end - start }
        var sidewalk: Int { isAvenue ? 3 : 2 }
    }

    /// The `index`th street on `axis`. Every fifth is an avenue, with two
    /// lanes each way and a median; the others have a lane each way.
    static func street(_ axis: Axis, _ index: Int) -> Street {
        let hash = Hash.of(index, salt: axis == .x ? 11 : 12)
        let isAvenue = floorModulo(index, 5) == 0
        // 3 m sidewalks, four 3 m lanes, two 1 m lane lines and a 2 m median;
        // or 2 m sidewalks, two 3 m lanes and a 1 m center line.
        let width = isAvenue ? 22 : 11
        let center = index * streetPitch + Int(hash % 25) - 12
        let start = center - width / 2
        return Street(index: index, start: start, end: start + width, isAvenue: isAvenue)
    }

    /// The street on `axis` that covers `coordinate`, if one does.
    static func street(_ axis: Axis, containing coordinate: Int) -> Street? {
        let nearest = floorDivide(coordinate + streetPitch / 2, streetPitch)
        for index in (nearest - 1)...(nearest + 1) {
            let street = street(axis, index)
            if coordinate >= street.start && coordinate < street.end {
                return street
            }
        }
        return nil
    }

    /// The street on `axis` within `distance` of `coordinate`, if one is.
    static func street(_ axis: Axis, near coordinate: Int, within distance: Int) -> Street? {
        let nearest = floorDivide(coordinate + streetPitch / 2, streetPitch)
        for index in (nearest - 1)...(nearest + 1) {
            let street = street(axis, index)
            if coordinate >= street.start - distance && coordinate < street.end + distance {
                return street
            }
        }
        return nil
    }

    /// The ground's color at a column, if a street covers it.
    static func streetSurface(x: Int, z: Int) -> UInt8? {
        let alongZ = street(.x, containing: x)
        let alongX = street(.z, containing: z)
        switch (alongZ, alongX) {
        case (nil, nil):
            return nil
        case (let street?, nil):
            return roadSurface(across: x - street.start, along: z, of: street, crossing: .z)
        case (nil, let street?):
            return roadSurface(across: z - street.start, along: x, of: street, crossing: .x)
        case (let a?, let b?):
            // An intersection: sidewalk only at its corners.
            let onSidewalkA = isSidewalk(x - a.start, of: a)
            let onSidewalkB = isSidewalk(z - b.start, of: b)
            return onSidewalkA && onSidewalkB ? Palette.sidewalk : Palette.asphalt
        }
    }

    private static func isSidewalk(_ across: Int, of street: Street) -> Bool {
        across < street.sidewalk || across >= street.width - street.sidewalk
    }

    private static func roadSurface(across: Int, along: Int, of street: Street, crossing: Axis) -> UInt8 {
        if isSidewalk(across, of: street) {
            return Palette.sidewalk
        }
        let lane = across - street.sidewalk
        // Zebra crossings just before each intersection.
        if let crossingStreet = Self.street(crossing, near: along, within: 4),
            along < crossingStreet.start || along >= crossingStreet.end
        {
            return lane.isMultiple(of: 2) ? Palette.marking : Palette.asphalt
        }
        let dashed = floorModulo(along, 6) < 3
        if street.isAvenue {
            switch lane {
            case 3, 12: return dashed ? Palette.marking : Palette.asphalt
            case 7, 8: return Palette.darkGrass
            default: return Palette.asphalt
            }
        }
        return lane == 3 ? (dashed ? Palette.centerLine : Palette.asphalt) : Palette.asphalt
    }

    // MARK: Blocks

    struct Rect {
        var x0: Int
        var z0: Int
        var x1: Int
        var z1: Int

        var width: Int { x1 - x0 }
        var depth: Int { z1 - z0 }
        var isEmpty: Bool { x1 <= x0 || z1 <= z0 }

        func intersects(_ other: Rect) -> Bool {
            x0 < other.x1 && other.x0 < x1 && z0 < other.z1 && other.z0 < z1
        }

        func intersection(_ other: Rect) -> Rect {
            Rect(x0: max(x0, other.x0), z0: max(z0, other.z0), x1: min(x1, other.x1), z1: min(z1, other.z1))
        }

        func inset(_ amount: Int) -> Rect {
            Rect(x0: x0 + amount, z0: z0 + amount, x1: x1 - amount, z1: z1 - amount)
        }
    }

    /// The block between streets `i` and `i + 1` on x, and `j` and `j + 1` on
    /// z.
    static func blockRect(_ i: Int, _ j: Int) -> Rect {
        Rect(x0: street(.x, i).end, z0: street(.z, j).end, x1: street(.x, i + 1).start, z1: street(.z, j + 1).start)
    }

    /// The indices of the blocks on `axis` that may overlap `lower..<upper`.
    static func blockIndices(from lower: Int, to upper: Int) -> ClosedRange<Int> {
        (floorDivide(lower, streetPitch) - 1)...(floorDivide(upper, streetPitch) + 1)
    }

    /// How built up the city is around a point, from 0, houses, to 1,
    /// towers.
    static func density(x: Int, z: Int) -> Float {
        let fx = Float(x)
        let fz = Float(z)
        let noise =
            valueNoise(x: fx, z: fz, scale: 900, salt: 21) * 0.6
            + valueNoise(x: fx, z: fz, scale: 260, salt: 22) * 0.4
        return smoothstep(0.3, 0.72, noise)
    }

    /// What a block holds: the ground of its lots, painted in order, and the
    /// buildings and trees on them.
    struct BlockPlan {
        var rect: Rect
        var grounds: [(rect: Rect, color: UInt8)] = []
        var buildings: [Building] = []
        var trees: [Tree] = []
    }

    static func blockPlan(_ i: Int, _ j: Int) -> BlockPlan {
        let rect = blockRect(i, j)
        var plan = BlockPlan(rect: rect)
        guard !rect.isEmpty else { return plan }
        var random = SeededRandom(seed: Hash.of(i, j, salt: 31))
        let density = density(x: (rect.x0 + rect.x1) / 2, z: (rect.z0 + rect.z1) / 2)

        if random.chance(density < 0.3 ? 0.1 : 0.05) {
            addPark(rect, to: &plan, random: &random)
            return plan
        }

        // Lots grow with the density: houses, then apartments, then towers.
        let largest = density < 0.25 ? 16 : density < 0.55 ? 28 : 46
        var lots: [Rect] = []
        split(rect, largest: largest, into: &lots, random: &random)
        for lot in lots {
            let onStreet = lot.x0 == rect.x0 || lot.z0 == rect.z0 || lot.x1 == rect.x1 || lot.z1 == rect.z1
            let lotDensity = min(max(density + (random.unit() - 0.5) * 0.3, 0), 1)
            if !onStreet && random.chance(0.6) {
                // A courtyard.
                plan.grounds.append((lot, Palette.grass))
                addTrees(in: lot.inset(1), spacing: 5, chance: 0.45, to: &plan, random: &random)
                continue
            }
            addBuilding(on: lot, density: lotDensity, to: &plan, random: &random)
        }
        return plan
    }

    /// Splits `rect` across its longer side until no side is longer than
    /// `largest`, into lots of any size from half that up.
    private static func split(_ rect: Rect, largest: Int, into lots: inout [Rect], random: inout SeededRandom) {
        let smallest = max(largest / 2, 6)
        let alongX = rect.width >= rect.depth
        let length = alongX ? rect.width : rect.depth
        guard length > largest, length >= smallest * 2 else {
            lots.append(rect)
            return
        }
        let cut = random.int(in: smallest...(length - smallest))
        if alongX {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x0 + cut, z1: rect.z1), largest: largest, into: &lots, random: &random)
            split(Rect(x0: rect.x0 + cut, z0: rect.z0, x1: rect.x1, z1: rect.z1), largest: largest, into: &lots, random: &random)
        } else {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x1, z1: rect.z0 + cut), largest: largest, into: &lots, random: &random)
            split(Rect(x0: rect.x0, z0: rect.z0 + cut, x1: rect.x1, z1: rect.z1), largest: largest, into: &lots, random: &random)
        }
    }

    private static func addPark(_ rect: Rect, to plan: inout BlockPlan, random: inout SeededRandom) {
        plan.grounds.append((rect, Palette.grass))
        // Paths across the middle.
        let midX = (rect.x0 + rect.x1) / 2
        let midZ = (rect.z0 + rect.z1) / 2
        plan.grounds.append((Rect(x0: midX - 1, z0: rect.z0, x1: midX + 1, z1: rect.z1), Palette.plaza))
        plan.grounds.append((Rect(x0: rect.x0, z0: midZ - 1, x1: rect.x1, z1: midZ + 1), Palette.plaza))
        addTrees(in: rect.inset(2), spacing: 6, chance: 0.75, avoiding: (midX, midZ), to: &plan, random: &random)
    }

    private static func addTrees(
        in rect: Rect, spacing: Int, chance: Float, avoiding paths: (x: Int, z: Int)? = nil, to plan: inout BlockPlan,
        random: inout SeededRandom
    ) {
        guard !rect.isEmpty else { return }
        var z = rect.z0 + spacing / 2
        while z < rect.z1 {
            var x = rect.x0 + spacing / 2
            while x < rect.x1 {
                let tx = min(max(x + random.int(in: -1...1), rect.x0), rect.x1 - 1)
                let tz = min(max(z + random.int(in: -1...1), rect.z0), rect.z1 - 1)
                let onPath = paths.map { abs(tx - $0.x) < 3 || abs(tz - $0.z) < 3 } ?? false
                if random.chance(chance) && !onPath {
                    let radius = random.chance(0.35) ? 2 : 1
                    plan.trees.append(
                        Tree(x: tx, z: tz, trunk: random.int(in: 1...3) + radius - 1, radius: radius,
                             leaves: random.pick(Palette.leaves)))
                }
                x += spacing
            }
            z += spacing
        }
    }

    private static func addBuilding(on lot: Rect, density: Float, to plan: inout BlockPlan, random: inout SeededRandom) {
        enum Kind { case house, apartment, office, tower }
        let shortSide = min(lot.width, lot.depth)
        let kind: Kind =
            density < 0.25 ? .house
            : density < 0.5 ? .apartment
            : density < 0.75 || shortSide < 20 ? .office
            : .tower

        // Each side sets back on its own, leaving at least a 5 m footprint.
        func setback(_ range: ClosedRange<Int>, _ length: Int) -> (Int, Int) {
            let room = max((length - 5) / 2, 0)
            return (min(random.int(in: range), room), min(random.int(in: range), room))
        }
        let setbackRange: ClosedRange<Int> =
            switch kind {
            case .house: 1...3
            case .apartment: 0...2
            case .office: 1...3
            case .tower: 2...4
            }
        let (west, east) = setback(setbackRange, lot.width)
        let (north, south) = setback(setbackRange, lot.depth)
        let footprint = Rect(x0: lot.x0 + west, z0: lot.z0 + north, x1: lot.x1 - east, z1: lot.z1 - south)

        var building = Building(footprint: footprint)
        switch kind {
        case .house:
            plan.grounds.append((lot, Palette.grass))
            building.height = random.int(in: 1...3) * floorHeight
            building.wall = random.pick(Palette.houseWalls)
            building.window = Palette.glass[2]
            building.roof = random.pick(Palette.houseRoofs)
            building.windows = .punched
            building.roofShape = footprint.width >= footprint.depth ? .gableAlongX : .gableAlongZ
        case .apartment:
            plan.grounds.append((lot, random.chance(0.5) ? Palette.grass : Palette.plaza))
            building.height = random.int(in: 4...(4 + Int(density * 16))) * floorHeight
            building.wall = random.pick(Palette.apartmentWalls)
            building.window = random.pick(Palette.glass)
            building.roof = random.pick(Palette.flatRoofs)
            building.windows = .columns(pitch: random.int(in: 2...3))
        case .office:
            plan.grounds.append((lot, Palette.plaza))
            building.height = random.int(in: 6...(8 + Int(density * 24))) * floorHeight
            building.wall = random.pick(Palette.officeWalls)
            building.window = random.pick(Palette.glass)
            building.roof = random.pick(Palette.flatRoofs)
            building.windows = random.chance(0.5) ? .ribbon : .columns(pitch: 2)
        case .tower:
            plan.grounds.append((lot, Palette.plaza))
            let floors = random.int(in: 20...(24 + Int(density * density * 56)))
            building.height = floors * floorHeight
            building.wall = random.pick(Palette.officeWalls)
            building.window = random.pick(Palette.glass)
            building.roof = random.pick(Palette.flatRoofs)
            building.windows = random.chance(0.6) ? .ribbon : .columns(pitch: 2)
            // Setbacks, while the footprint stays at least 8 m across.
            var inset = 0
            var level = Float(0.45) + random.unit() * 0.2
            for _ in 0..<2 {
                let step = random.int(in: 2...4)
                guard min(footprint.width, footprint.depth) - 2 * (inset + step) >= 8 else { break }
                inset += step
                let fromY = Int(Float(floors) * level) * floorHeight + 1
                building.tiers.append((fromY: fromY, inset: inset))
                level += 0.2 + random.unit() * 0.1
            }
            if random.chance(0.5) {
                // A mast at the center of the roof.
                let cx = (footprint.x0 + footprint.x1) / 2
                let cz = (footprint.z0 + footprint.z1) / 2
                building.equipment.append(
                    Box(x0: cx, y0: building.height, z0: cz, x1: cx + 1, y1: building.height + random.int(in: 8...20),
                        z1: cz + 1, color: Palette.equipment))
            }
        }

        if building.roofShape == .flat {
            addRoofEquipment(to: &building, random: &random)
        }
        plan.buildings.append(building)
    }

    private static func addRoofEquipment(to building: inout Building, random: inout SeededRandom) {
        let roof = building.footprint(atY: building.height).inset(2)
        guard roof.width >= 4, roof.depth >= 4 else { return }
        for _ in 0..<random.int(in: 0...2) {
            let width = random.int(in: 2...min(5, roof.width))
            let depth = random.int(in: 2...min(5, roof.depth))
            let x0 = random.int(in: roof.x0...(roof.x1 - width))
            let z0 = random.int(in: roof.z0...(roof.z1 - depth))
            building.equipment.append(
                Box(x0: x0, y0: building.height, z0: z0, x1: x0 + width, y1: building.height + random.int(in: 1...3),
                    z1: z0 + depth, color: Palette.equipment))
        }
    }

    // MARK: Street trees

    /// The trees along the sidewalks of streets that pass through `region`.
    static func streetTrees(in region: Rect) -> [Tree] {
        var trees: [Tree] = []
        for axis in [Axis.x, Axis.z] {
            let (lower, upper) = axis == .x ? (region.x0, region.x1) : (region.z0, region.z1)
            let (alongLower, alongUpper) = axis == .x ? (region.z0, region.z1) : (region.x0, region.x1)
            for index in blockIndices(from: lower, to: upper) {
                let street = street(axis, index)
                guard street.end + 2 > lower, street.start - 2 < upper else { continue }
                let spacing = 9
                let offset = Int(Hash.of(index, salt: axis == .x ? 41 : 42) % UInt64(spacing))
                var along = alongLower - 2 + floorModulo(offset - (alongLower - 2), spacing)
                while along < alongUpper + 2 {
                    defer { along += spacing }
                    // Not near crossings.
                    if Self.street(axis.other, near: along, within: 6) != nil { continue }
                    let hash = Hash.of(index, along, salt: 43)
                    for across in [street.start + street.sidewalk - 1, street.end - street.sidewalk] {
                        let (x, z) = axis == .x ? (across, along) : (along, across)
                        trees.append(
                            Tree(x: x, z: z, trunk: 2, radius: 1, leaves: Palette.leaves[Int(hash % 3)]))
                    }
                }
            }
        }
        return trees
    }
}

/// A box of one color, from its lower corner up to, but not including, its
/// upper one.
struct Box {
    var x0: Int
    var y0: Int
    var z0: Int
    var x1: Int
    var y1: Int
    var z1: Int
    var color: UInt8
}

/// A building on the ground, whose walls fill y from 1 through `height`.
struct Building {
    enum Windows {
        /// Single windows two rows tall, every third column.
        case punched
        /// Windows `pitch - 1` columns wide between single pillars.
        case columns(pitch: Int)
        /// Glass all around between the slabs.
        case ribbon
    }

    enum RoofShape {
        case flat
        /// A stepped gable roof whose ridge runs along x.
        case gableAlongX
        case gableAlongZ
    }

    var x0: Int
    var z0: Int
    var x1: Int
    var z1: Int
    var height = 3
    var wall = Palette.houseWalls[0]
    var window = Palette.glass[0]
    var roof = Palette.flatRoofs[0]
    var windows = Windows.punched
    var roofShape = RoofShape.flat
    /// From each `fromY` up, the footprint shrinks by `inset` on every side.
    var tiers: [(fromY: Int, inset: Int)] = []
    var equipment: [Box] = []

    init(footprint: CityLayout.Rect) {
        x0 = footprint.x0
        z0 = footprint.z0
        x1 = footprint.x1
        z1 = footprint.z1
    }

    /// The highest y that holds a voxel of the building.
    var top: Int {
        var top = height
        switch roofShape {
        case .flat: break
        case .gableAlongX: top += (z1 - z0 + 1) / 2
        case .gableAlongZ: top += (x1 - x0 + 1) / 2
        }
        for box in equipment {
            top = max(top, box.y1 - 1)
        }
        return top
    }

    var bounds: CityLayout.Rect {
        CityLayout.Rect(x0: x0, z0: z0, x1: x1, z1: z1)
    }

    func footprint(atY y: Int) -> CityLayout.Rect {
        var inset = 0
        for tier in tiers where y >= tier.fromY {
            inset = tier.inset
        }
        return bounds.inset(inset)
    }

    private func bodyContains(x: Int, y: Int, z: Int) -> Bool {
        guard y >= 1 && y <= height else { return false }
        let rect = footprint(atY: y)
        return x >= rect.x0 && x < rect.x1 && z >= rect.z0 && z < rect.z1
    }

    /// The voxel's color at a point, or air.
    func voxel(x: Int, y: Int, z: Int) -> UInt8 {
        if bodyContains(x: x, y: y, z: z) {
            return bodyVoxel(x: x, y: y, z: z)
        }
        if y > height {
            if let color = gableVoxel(x: x, y: y, z: z) {
                return color
            }
        }
        for box in equipment
        where x >= box.x0 && x < box.x1 && y >= box.y0 && y < box.y1 && z >= box.z0 && z < box.z1 {
            return box.color
        }
        return Palette.air
    }

    /// Whether the body has a voxel at a point: a flat roof is sunken a
    /// voxel inside its parapet.
    private func bodySolid(x: Int, y: Int, z: Int) -> Bool {
        guard bodyContains(x: x, y: y, z: z) else { return false }
        return !(roofShape == .flat && y == height && !isShell(x: x, y: y, z: z))
    }

    private func isShell(x: Int, y: Int, z: Int) -> Bool {
        let rect = footprint(atY: y)
        return x == rect.x0 || x == rect.x1 - 1 || z == rect.z0 || z == rect.z1 - 1
    }

    private func bodyVoxel(x: Int, y: Int, z: Int) -> UInt8 {
        guard bodySolid(x: x, y: y, z: z) else { return Palette.air }
        let rect = footprint(atY: y)
        let onX = x == rect.x0 || x == rect.x1 - 1
        let onZ = z == rect.z0 || z == rect.z1 - 1
        // Under a gable roof, or under more of the body.
        let exposed = !(roofShape != .flat && y == height) && !bodySolid(x: x, y: y + 1, z: z)
        guard onX || onZ else {
            // Hidden inside, but for roofs.
            return exposed ? roof : wall
        }
        let row = (y - 1) % CityLayout.floorHeight
        if exposed || row == 0 || (onX && onZ) {
            return wall
        }
        let column = onX ? z - rect.z0 : x - rect.x0
        switch windows {
        case .punched:
            return column % 3 == 1 ? window : wall
        case .columns(let pitch):
            return column % pitch == 0 ? wall : window
        case .ribbon:
            return window
        }
    }

    private func gableVoxel(x: Int, y: Int, z: Int) -> UInt8? {
        guard x >= x0 && x < x1 && z >= z0 && z < z1 else { return nil }
        let layer = y - height
        let (across, span, atEnd): (Int, Int, Bool)
        switch roofShape {
        case .flat: return nil
        case .gableAlongX: (across, span, atEnd) = (z - z0, z1 - z0, x == x0 || x == x1 - 1)
        case .gableAlongZ: (across, span, atEnd) = (x - x0, x1 - x0, z == z0 || z == z1 - 1)
        }
        let low = layer - 1
        let high = span - layer
        guard across >= low && across <= high else { return nil }
        let isSlope = across == low || across == high || high - low < 2
        return isSlope || !atEnd ? roof : wall
    }
}

/// A tree: a trunk and a box of leaves with its corners cut.
struct Tree {
    var x: Int
    var z: Int
    /// The height of the trunk below the leaves.
    var trunk: Int
    var radius: Int
    var leaves: UInt8

    private var layers: Int { radius + 2 }
    var top: Int { trunk + layers }

    var bounds: CityLayout.Rect {
        CityLayout.Rect(x0: x - radius, z0: z - radius, x1: x + radius + 1, z1: z + radius + 1)
    }

    func voxel(x: Int, y: Int, z: Int) -> UInt8 {
        let dx = abs(x - self.x)
        let dz = abs(z - self.z)
        let layer = y - trunk - 1
        if layer >= 0 && layer < layers {
            let isEnd = layer == 0 || layer == layers - 1
            let reach = radius >= 2 && isEnd ? radius - 1 : radius
            let cutsCorners = radius >= 2 ? reach == radius : layer == layers - 1
            if dx <= reach && dz <= reach && !(cutsCorners && dx == reach && dz == reach) {
                return leaves
            }
        }
        if dx == 0 && dz == 0 && y >= 1 && y <= trunk {
            return Palette.trunk
        }
        return Palette.air
    }
}

@inline(__always)
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
