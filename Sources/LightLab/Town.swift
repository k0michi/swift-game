import VectorMath

/// Random numbers from a seed, the same on every platform.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Random numbers for one thing in the world, from what identifies it.
    init(seed: UInt64, salt: UInt64, _ a: Float, _ b: Float) {
        var mixer = SeededRandom(seed: seed ^ (salt &* 0x9E37_79B9_7F4A_7C15))
        let first = mixer.next() ^ UInt64(bitPattern: Int64(cells(a)))
        var second = SeededRandom(seed: first)
        self.init(seed: second.next() ^ UInt64(bitPattern: Int64(cells(b))))
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number from 0 up to 1.
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func float(_ low: Float, _ high: Float) -> Float {
        low + (high - low) * unit()
    }

    mutating func int(_ low: Int, _ high: Int) -> Int {
        low + Int(next() % UInt64(high - low + 1))
    }

    mutating func chance(_ probability: Float) -> Bool {
        unit() < probability
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[Int(next() % UInt64(values.count))]
    }
}

/// Any part of an endless town, worked out from a seed alone: roads at
/// uneven spacing, a railway with a level crossing wherever a road meets it,
/// and lots of buildings between them.
///
/// Everything is placed by where it is, not by what was made before it, so
/// that a region comes out the same however it is cut up.
struct Town {
    private static let level = Scene.streetLevel
    private static let roadSpacing: Float = 52
    private static let railHalf: Float = 5
    /// How far past a region to look, for anything that reaches into it.
    private static let lookAround: Float = 140
    /// How far apart along the railway the busy places are.
    private static let stationSpacing: Float = 240
    private static let stationReach: Float = 62

    /// A road along one axis, at `center` on the other.
    private struct Road {
        var center: Float
        var isMain: Bool
        var half: Float { isMain ? 5.5 : 3.75 }
        var carriageHalf: Float { isMain ? 4 : 2.25 }
    }

    private enum Axis {
        case x, z
        var salt: UInt64 { self == .x ? 11 : 12 }
    }

    /// The voxels of the region.
    private(set) var grid: VoxelGrid
    /// The lamps whose positions are in the region.
    private(set) var lights: [PointLight] = []

    private let seed: UInt64
    private let originX: Int
    private let originZ: Int
    // The region's edges, in meters.
    private let lowX: Float
    private let highX: Float
    private let lowZ: Float
    private let highZ: Float
    private let railZ: Float
    /// Roads running along z, by their x; and along x, by their z.
    private var alongZ: [Road] = []
    private var alongX: [Road] = []
    /// The lots still to build, last first.
    private var pendingLots: [PendingLot] = []

    /// Builds the voxels over `x` and `z`, a range of voxels each way. With
    /// `lotsLater`, the lots wait for `buildNextLot`, so that the work can be
    /// spread over frames.
    init(seed: UInt64, x: Range<Int>, z: Range<Int>, lotsLater: Bool = false) {
        self.seed = seed
        originX = x.lowerBound
        originZ = z.lowerBound
        let scale = 1 / Float(voxelsPerMeter)
        lowX = Float(x.lowerBound) * scale
        highX = Float(x.upperBound) * scale
        lowZ = Float(z.lowerBound) * scale
        highZ = Float(z.upperBound) * scale
        railZ = Self.railZ(seed: seed)
        grid = VoxelGrid(width: x.count, height: cells(Scene.size.height), depth: z.count)
        alongZ = Self.roads(.z, from: lowX - Self.lookAround, to: highX + Self.lookAround, seed: seed, railZ: railZ)
        alongX = Self.roads(.x, from: lowZ - Self.lookAround, to: highZ + Self.lookAround, seed: seed, railZ: railZ)
        buildGround()
        buildRailway()
        buildMarkings()
        buildStreetFurniture()
        findLots()
        if !lotsLater {
            while buildNextLot() {}
        }
    }

    /// Builds one more lot, and says whether any are left.
    mutating func buildNextLot() -> Bool {
        guard let next = pendingLots.popLast() else { return false }
        buildLot(next.lot, in: next.block, roadSides: next.roadSides)
        return !pendingLots.isEmpty
    }

    /// Where someone on foot may start: on a road, near a point.
    static func spawn(seed: UInt64, near point: Vector2<Float>) -> Vector2<Float> {
        let rail = railZ(seed: seed)
        func nearest(_ roads: [Road], _ value: Float) -> Float {
            roads.min { abs($0.center - value) < abs($1.center - value) }?.center ?? value
        }
        return Vector2(
            nearest(roads(.z, from: point.x - 120, to: point.x + 120, seed: seed, railZ: rail), point.x),
            nearest(roads(.x, from: point.y - 120, to: point.y + 120, seed: seed, railZ: rail), point.y))
    }

    // MARK: Layout

    private static func railZ(seed: UInt64) -> Float {
        var random = SeededRandom(seed: seed, salt: 21, 0, 0)
        return random.float(92, 108).rounded()
    }

    /// The roads along an axis with centers from `low` to `high`. Roads
    /// along z are spaced over x; those along x, over z, and not too near
    /// the railway. Each is where its number says, whatever is asked for.
    private static func roads(_ runsAlong: Axis, from low: Float, to high: Float, seed: UInt64, railZ: Float) -> [Road] {
        var roads: [Road] = []
        let first = Int((low / roadSpacing).rounded(.down)) - 1
        let last = Int((high / roadSpacing).rounded(.up)) + 1
        for number in first...last {
            var random = SeededRandom(seed: seed, salt: runsAlong.salt, Float(number), 0)
            let center = (Float(number) * roadSpacing + random.float(-10, 10)).rounded()
            guard center >= low, center <= high else { continue }
            if runsAlong == .x && abs(center - railZ) <= 16 { continue }
            roads.append(Road(center: center, isMain: number % 3 == 0 || random.chance(0.3)))
        }
        return roads
    }

    private mutating func box(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float, _ material: UInt8
    ) {
        guard x0 < x1, y0 < y1, z0 < z1 else { return }
        grid.fill(
            x: (cells(x0) - originX)..<(cells(x1) - originX), y: cells(y0)..<cells(y1),
            z: (cells(z0) - originZ)..<(cells(z1) - originZ), material)
    }

    /// Fills a box given across and along a road, which runs along z or x.
    private mutating func band(
        runsAlongZ: Bool, _ across0: Float, _ across1: Float, _ y0: Float, _ y1: Float, _ along0: Float, _ along1: Float,
        _ material: UInt8
    ) {
        if runsAlongZ {
            box(across0, across1, y0, y1, along0, along1, material)
        } else {
            box(along0, along1, y0, y1, across0, across1, material)
        }
    }

    private func contains(x: Float, z: Float) -> Bool {
        x >= lowX && x < highX && z >= lowZ && z < highZ
    }

    private mutating func light(
        _ x: Float, _ y: Float, _ z: Float, color: UInt32, intensity: Float, radius: Float, _ schedule: Material.Schedule
    ) {
        guard contains(x: x, z: z) else { return }
        lights.append(
            PointLight(
                position: Vector3(x, y, z), color: Material(color: color).linearColor * intensity, radius: radius,
                schedule: schedule))
    }

    private mutating func buildGround() {
        let level = Self.level
        let (x0, x1, z0, z1) = (lowX, highX, lowZ, highZ)
        box(x0, x1, 0, level, z0, z1, Materials.soil)
        box(x0, x1, level - 0.125, level, z0, z1, Materials.concrete)
        // Sidewalks first, then every carriageway across them, so that the
        // roads open into one another at the intersections.
        for road in alongZ {
            box(road.center - road.half, road.center + road.half, level, level + 0.125, z0, z1, Materials.sidewalk)
        }
        for road in alongX {
            box(x0, x1, level, level + 0.125, road.center - road.half, road.center + road.half, Materials.sidewalk)
        }
        for road in alongZ {
            let (a, b) = (road.center - road.carriageHalf, road.center + road.carriageHalf)
            box(a, b, level, level + 0.125, z0, z1, Materials.air)
            box(a, b, level - 0.125, level, z0, z1, Materials.asphalt)
        }
        for road in alongX {
            let (a, b) = (road.center - road.carriageHalf, road.center + road.carriageHalf)
            box(x0, x1, level, level + 0.125, a, b, Materials.air)
            box(x0, x1, level - 0.125, level, a, b, Materials.asphalt)
        }
    }

    /// The stretches between what crosses a line, from one to the next.
    /// Only those with something at both ends, so as not to depend on how
    /// far was looked.
    private func stretches(between obstacles: [(center: Float, half: Float)]) -> [(Float, Float)] {
        let sorted = obstacles.sorted { $0.center < $1.center }
        guard sorted.count > 1 else { return [] }
        return (0..<(sorted.count - 1)).compactMap { index in
            let start = sorted[index].center + sorted[index].half
            let end = sorted[index + 1].center - sorted[index + 1].half
            return start < end ? (start, end) : nil
        }
    }

    // MARK: Railway

    private mutating func buildRailway() {
        let level = Self.level
        let z = railZ
        guard z + Self.railHalf + 1 > lowZ, z - Self.railHalf - 1 < highZ else { return }
        for (x0, x1) in stretches(between: alongZ.map { ($0.center, $0.half) }) where x1 > lowX && x0 < highX {
            box(x0, x1, level, level + 0.125, z - 3.5, z + 3.5, Materials.ballast)
            box(x0, x1, level + 0.125, level + 0.25, z - 3, z + 3, Materials.ballast)
            var x = x0 + 0.25
            while x + 0.25 < x1 {
                box(x, x + 0.25, level + 0.25, level + 0.375, z - 1, z + 1, Materials.sleeper)
                x += 0.625
            }
            // Fences on both sides, on posts.
            for fenceZ in [z - 4.5, z + 4.375] {
                box(x0, x1, level + 1.125, level + 1.25, fenceZ, fenceZ + 0.125, Materials.darkSteel)
                var post = x0 + 0.5
                while post < x1 - 0.5 {
                    box(post, post + 0.125, level, level + 1.25, fenceZ, fenceZ + 0.125, Materials.darkSteel)
                    post += 2
                }
            }
        }
        // Each road crosses on a deck, and the signals ring on both sides.
        for road in alongZ {
            let (x0, x1) = (road.center - road.half, road.center + road.half)
            box(x0, x1, level, level + 0.125, z - 3.5, z + 3.5, Materials.air)
            box(x0, x1, level - 0.125, level + 0.125, z - 3, z + 3, Materials.crossingDeck)
            crossingSignal(x: road.center - road.carriageHalf - 0.75, z: z - 3.75)
            crossingSignal(x: road.center + road.carriageHalf + 0.5, z: z + 3.5)
        }
        // The rails run unbroken.
        for rail in [z - 0.625, z + 0.5] {
            box(lowX, highX, level + 0.375, level + 0.625, rail, rail + 0.125, Materials.rail)
        }
    }

    private mutating func crossingSignal(x: Float, z: Float) {
        let base = Self.level
        var y = base
        var stripe = false
        while y < base + 2.5 {
            box(x, x + 0.25, y, y + 0.25, z, z + 0.25, stripe ? Materials.stripeBlack : Materials.stripeYellow)
            y += 0.25
            stripe.toggle()
        }
        box(x - 0.5, x + 0.75, base + 3, base + 3.125, z, z + 0.25, Materials.stripeYellow)
        for (offset, lamp, schedule) in [
            (Float(-0.5), Materials.crossingLampA, Material.Schedule.blinkA),
            (Float(0.5), Materials.crossingLampB, Material.Schedule.blinkB),
        ] {
            box(x + offset, x + offset + 0.25, base + 2.25, base + 2.625, z - 0.125, z + 0.375, Materials.stripeBlack)
            box(x + offset, x + offset + 0.25, base + 2.25, base + 2.5, z - 0.25, z - 0.125, lamp)
            box(x + offset, x + offset + 0.25, base + 2.25, base + 2.5, z + 0.375, z + 0.5, lamp)
            light(x + offset + 0.125, base + 2.375, z + 0.125, color: 0xff2a1a, intensity: 6, radius: 5, schedule)
        }
    }

    // MARK: Roads

    private mutating func buildMarkings() {
        let y0 = Self.level - 0.125
        let y1 = Self.level
        for (roads, others, runsAlongZ) in [(alongZ, alongX, true), (alongX, alongZ, false)] {
            for road in roads where road.isMain {
                var obstacles = others.map { (center: $0.center, half: $0.half + 3) }
                if runsAlongZ { obstacles.append((railZ, Self.railHalf)) }
                for (a0, a1) in stretches(between: obstacles) {
                    // A broken center line.
                    var along = a0
                    while along < a1 {
                        band(runsAlongZ: runsAlongZ, road.center - 0.125, road.center, y0, y1, along, min(along + 2.5, a1), Materials.lineYellow)
                        along += 5
                    }
                    for side in [-Float(1), 1] {
                        let edge = road.center + side * (road.carriageHalf - 0.375)
                        band(runsAlongZ: runsAlongZ, edge - 0.0625, edge + 0.0625, y0, y1, a0, a1, Materials.lineWhite)
                    }
                }
                // Zebra crossings on the way into each intersection.
                for other in others {
                    for side in [-Float(1), 1] {
                        let near = other.center + side * (other.half + 0.25)
                        let (a0, a1) = side < 0 ? (near - 2.5, near) : (near, near + 2.5)
                        var across = road.center - road.carriageHalf + 0.5
                        while across + 0.5 < road.center + road.carriageHalf {
                            band(runsAlongZ: runsAlongZ, across, across + 0.5, y0, y1, a0, a1, Materials.lineWhite)
                            across += 1
                        }
                    }
                }
            }
        }
    }

    private mutating func buildStreetFurniture() {
        for (roads, others, runsAlongZ) in [(alongZ, alongX, true), (alongX, alongZ, false)] {
            for road in roads {
                var obstacles = others.map { (center: $0.center, half: $0.half + 2) }
                if runsAlongZ { obstacles.append((railZ, Self.railHalf + 1)) }
                for (a0, a1) in stretches(between: obstacles) {
                    var random = SeededRandom(seed: seed, salt: runsAlongZ ? 31 : 32, road.center, a0)
                    var along = a0 + random.float(3, 9)
                    var side: Float = random.chance(0.5) ? -1 : 1
                    while along < a1 - 1 {
                        if road.isMain || random.chance(0.8) {
                            streetLamp(road: road, runsAlongZ: runsAlongZ, along: along, side: side)
                        } else {
                            utilityPole(road: road, runsAlongZ: runsAlongZ, along: along, side: side)
                        }
                        along += random.float(16, 24)
                        side = -side
                    }
                }
            }
        }
        // A signal at each meeting of main roads.
        for road in alongZ where road.isMain {
            for cross in alongX where cross.isMain {
                trafficSignal(x: road.center + road.carriageHalf + 0.5, z: cross.center + cross.carriageHalf + 0.5)
            }
        }
    }

    private mutating func streetLamp(road: Road, runsAlongZ: Bool, along: Float, side: Float) {
        let base = Self.level + 0.125
        let across = road.center + side * (road.carriageHalf + 0.625)
        let reach = across - side * 1.25
        let height: Float = 5.5
        let (a0, a1) = (min(across, reach), max(across, reach) + 0.25)
        band(runsAlongZ: runsAlongZ, across, across + 0.25, base, base + height, along, along + 0.25, Materials.darkSteel)
        band(runsAlongZ: runsAlongZ, a0, a1, base + height, base + height + 0.25, along, along + 0.25, Materials.darkSteel)
        band(runsAlongZ: runsAlongZ, reach, reach + 0.25, base + height - 0.125, base + height, along, along + 0.25, Materials.lampWarm)
        let (x, z) = runsAlongZ ? (reach + 0.125, along + 0.125) : (along + 0.125, reach + 0.125)
        light(x, base + height - 0.5, z, color: 0xffc890, intensity: 12, radius: 10, .night)
    }

    private mutating func utilityPole(road: Road, runsAlongZ: Bool, along: Float, side: Float) {
        let base = Self.level + 0.125
        let across = road.center + side * (road.carriageHalf + 0.75)
        band(runsAlongZ: runsAlongZ, across, across + 0.375, base, base + 8.5, along, along + 0.375, Materials.poleConcrete)
        band(runsAlongZ: runsAlongZ, across - 0.625, across + 1, base + 7.75, base + 7.875, along, along + 0.375, Materials.darkSteel)
    }

    private mutating func trafficSignal(x: Float, z: Float) {
        let base = Self.level + 0.125
        box(x, x + 0.25, base, base + 4.75, z, z + 0.25, Materials.darkSteel)
        box(x - 0.125, x + 0.375, base + 4, base + 4.5, z - 0.75, z + 1, Materials.darkSteel)
        let lamps: [(Float, UInt8, Material.Schedule, UInt32)] = [
            (-0.625, Materials.signalGreen, .signalGreen, 0x1affb0),
            (0, Materials.signalYellow, .signalYellow, 0xffb21a),
            (0.625, Materials.signalRed, .signalRed, 0xff2a1a),
        ]
        for (offset, lamp, schedule, color) in lamps {
            box(x - 0.25, x - 0.125, base + 4.125, base + 4.375, z + offset, z + offset + 0.375, lamp)
            light(x - 0.5, base + 4.25, z + offset + 0.1875, color: color, intensity: 3, radius: 4, schedule)
        }
    }

    // MARK: Blocks

    private struct Rect {
        var x0: Float
        var z0: Float
        var x1: Float
        var z1: Float
        var width: Float { x1 - x0 }
        var depth: Float { z1 - z0 }
    }

    private struct PendingLot {
        var lot: Rect
        var block: Rect
        var roadSides: (west: Bool, east: Bool, north: Bool, south: Bool)
    }

    private mutating func findLots() {
        let xObstacles = alongZ.map { (center: $0.center, half: $0.half) }
        let zObstacles = alongX.map { (center: $0.center, half: $0.half) } + [(railZ, Self.railHalf)]
        for (x0, x1) in stretches(between: xObstacles) where x1 - x0 >= 6 && x1 > lowX && x0 < highX {
            for (z0, z1) in stretches(between: zObstacles) where z1 - z0 >= 6 && z1 > lowZ && z0 < highZ {
                let block = Rect(x0: x0, z0: z0, x1: x1, z1: z1)
                let roadSides = (
                    west: alongZ.contains { $0.center + $0.half == x0 }, east: alongZ.contains { $0.center - $0.half == x1 },
                    north: alongX.contains { $0.center + $0.half == z0 }, south: alongX.contains { $0.center - $0.half == z1 }
                )
                var random = SeededRandom(seed: seed, salt: 41, x0, z0)
                let largest = random.float(13, 22)
                var lots: [Rect] = []
                Self.split(block, largest: largest, random: &random, into: &lots)
                for lot in lots where lot.x1 > lowX && lot.x0 < highX && lot.z1 > lowZ && lot.z0 < highZ {
                    pendingLots.append(PendingLot(lot: lot, block: block, roadSides: roadSides))
                }
            }
        }
    }

    private static func split(_ rect: Rect, largest: Float, random: inout SeededRandom, into lots: inout [Rect]) {
        let alongX = rect.width >= rect.depth
        let length = alongX ? rect.width : rect.depth
        guard length > largest, length >= 12 else {
            lots.append(rect)
            return
        }
        let cut = (length * random.float(0.38, 0.62)).rounded()
        if alongX {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x0 + cut, z1: rect.z1), largest: largest, random: &random, into: &lots)
            split(Rect(x0: rect.x0 + cut, z0: rect.z0, x1: rect.x1, z1: rect.z1), largest: largest, random: &random, into: &lots)
        } else {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x1, z1: rect.z0 + cut), largest: largest, random: &random, into: &lots)
            split(Rect(x0: rect.x0, z0: rect.z0 + cut, x1: rect.x1, z1: rect.z1), largest: largest, random: &random, into: &lots)
        }
    }

    /// Which way a lot's front looks.
    private enum Facing { case north, south, west, east }

    private mutating func buildLot(
        _ lot: Rect, in block: Rect, roadSides: (west: Bool, east: Bool, north: Bool, south: Bool)
    ) {
        // Facing the nearest road.
        var choices: [(Float, Facing)] = []
        if roadSides.north { choices.append((lot.z0 - block.z0, .north)) }
        if roadSides.south { choices.append((block.z1 - lot.z1, .south)) }
        if roadSides.west { choices.append((lot.x0 - block.x0, .west)) }
        if roadSides.east { choices.append((block.x1 - lot.x1, .east)) }
        let facing = choices.min { $0.0 < $1.0 }?.1 ?? .north
        let sideways = facing == .west || facing == .east
        var plot = Plot(width: sideways ? lot.depth : lot.width, depth: sideways ? lot.width : lot.depth)

        // Busier around the places along the railway.
        let centerX = (lot.x0 + lot.x1) / 2
        let centerZ = (lot.z0 + lot.z1) / 2
        let station = (centerX / Self.stationSpacing).rounded() * Self.stationSpacing
        let dx = centerX - station
        let dz = centerZ - railZ
        let isCentral = (dx * dx + dz * dz).squareRoot() < Self.stationReach
        var random = SeededRandom(seed: seed, salt: 42, lot.x0, lot.z0)
        plot.build(central: isCentral, random: &random)
        stamp(plot, at: lot, facing: facing)
    }

    /// Copies a plot into the region, turned to face the way it should.
    private mutating func stamp(_ plot: Plot, at lot: Rect, facing: Facing) {
        let (lotX, lotZ) = (cells(lot.x0) - originX, cells(lot.z0) - originZ)
        let (w, d) = (plot.grid.width, plot.grid.depth)
        // The plot's lowest layer is the town's ground layer.
        let lift = cells(Self.level) - 1
        for y in 0..<plot.grid.height {
            for z in 0..<d {
                for x in 0..<w {
                    let material = plot.grid.data[plot.grid.index(x, y, z)]
                    guard material != Materials.air else { continue }
                    let (worldX, worldZ): (Int, Int)
                    switch facing {
                    case .north: (worldX, worldZ) = (x, z)
                    case .south: (worldX, worldZ) = (w - 1 - x, d - 1 - z)
                    case .west: (worldX, worldZ) = (z, w - 1 - x)
                    case .east: (worldX, worldZ) = (d - 1 - z, x)
                    }
                    grid[lotX + worldX, lift + y, lotZ + worldZ] = material
                }
            }
        }
        let (width, depth) = (plot.width, plot.depth)
        for lamp in plot.lights {
            let (x, y, z) = (lamp.position.x, lamp.position.y, lamp.position.z)
            let (worldX, worldZ): (Float, Float)
            switch facing {
            case .north: (worldX, worldZ) = (x, z)
            case .south: (worldX, worldZ) = (width - x, depth - z)
            case .west: (worldX, worldZ) = (z, width - x)
            case .east: (worldX, worldZ) = (depth - z, x)
            }
            guard contains(x: lot.x0 + worldX, z: lot.z0 + worldZ) else { continue }
            var moved = lamp
            moved.position = Vector3(lot.x0 + worldX, y + Self.level, lot.z0 + worldZ)
            lights.append(moved)
        }
    }
}
