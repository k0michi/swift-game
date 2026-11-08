import VectorMath

/// Random numbers from a seed, the same on every platform.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
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

/// A town 200 m square, laid out from a seed: a grid of roads of uneven
/// spacing, all reaching one another and the edges of the town; a railway
/// from end to end, with a level crossing wherever a road meets it; and
/// lots of buildings between them.
struct Town {
    static let size: Float = 200
    private static let level = Scene.streetLevel

    /// A road along one axis, at `center` on the other.
    private struct Road {
        var center: Float
        var isMain: Bool
        var half: Float { isMain ? 5.5 : 3.75 }
        var carriageHalf: Float { isMain ? 4 : 2.25 }
    }

    private var grid: VoxelGrid
    private(set) var lights: [PointLight] = []
    private var random: SeededRandom
    /// Roads running along z, by their x; and along x, by their z.
    private var alongZ: [Road] = []
    private var alongX: [Road] = []
    private var railZ: Float = 0
    private static let railHalf: Float = 5

    private(set) var spawn = Vector2<Float>(100, 100)
    var voxels: VoxelGrid { grid }

    init(seed: UInt64) {
        random = SeededRandom(seed: seed)
        grid = VoxelGrid(width: cells(Self.size), height: cells(Scene.size.height), depth: cells(Self.size))
        layOutRoads()
        buildGround()
        buildRailway()
        buildMarkings()
        buildStreetFurniture()
        buildBlocks()
        let road = alongZ.min { abs($0.center - 100) < abs($1.center - 100) }!
        let cross = alongX.min { abs($0.center - 100) < abs($1.center - 100) }!
        spawn = Vector2(road.center, cross.center)
    }

    // MARK: Layout

    private mutating func spacedRoads() -> [Road] {
        var roads: [Road] = []
        var position = random.float(18, 30)
        while position < Self.size - 15 {
            roads.append(Road(center: position.rounded(), isMain: random.chance(0.45)))
            position += random.float(38, 62)
        }
        return roads
    }

    private mutating func layOutRoads() {
        alongZ = spacedRoads()
        railZ = random.float(92, 108).rounded()
        alongX = spacedRoads().filter { abs($0.center - railZ) > 16 }
        // The town's main street runs through its middle either way.
        if let index = alongZ.indices.min(by: { abs(alongZ[$0].center - 100) < abs(alongZ[$1].center - 100) }) {
            alongZ[index].isMain = true
        }
        if let index = alongX.indices.min(by: { abs(alongX[$0].center - 100) < abs(alongX[$1].center - 100) }) {
            alongX[index].isMain = true
        }
    }

    private mutating func box(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float, _ material: UInt8
    ) {
        guard x0 < x1, y0 < y1, z0 < z1 else { return }
        grid.fill(x: x0...x1, y: y0...y1, z: z0...z1, material)
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

    private mutating func light(
        _ x: Float, _ y: Float, _ z: Float, color: UInt32, intensity: Float, radius: Float, _ schedule: Material.Schedule
    ) {
        lights.append(
            PointLight(
                position: Vector3(x, y, z), color: Material(color: color).linearColor * intensity, radius: radius,
                schedule: schedule))
    }

    private mutating func buildGround() {
        let (size, level) = (Self.size, Self.level)
        box(0, size, 0, level, 0, size, Materials.soil)
        box(0, size, level - 0.125, level, 0, size, Materials.concrete)
        // Sidewalks first, then every carriageway across them, so that the
        // roads open into one another at the intersections.
        for road in alongZ {
            box(road.center - road.half, road.center + road.half, level, level + 0.125, 0, size, Materials.sidewalk)
        }
        for road in alongX {
            box(0, size, level, level + 0.125, road.center - road.half, road.center + road.half, Materials.sidewalk)
        }
        for road in alongZ {
            let (x0, x1) = (road.center - road.carriageHalf, road.center + road.carriageHalf)
            box(x0, x1, level, level + 0.125, 0, size, Materials.air)
            box(x0, x1, level - 0.125, level, 0, size, Materials.asphalt)
        }
        for road in alongX {
            let (z0, z1) = (road.center - road.carriageHalf, road.center + road.carriageHalf)
            box(0, size, level, level + 0.125, z0, z1, Materials.air)
            box(0, size, level - 0.125, level, z0, z1, Materials.asphalt)
        }
    }

    /// The stretches of a line of the town left by what crosses it.
    private func stretches(between obstacles: [(center: Float, half: Float)]) -> [(Float, Float)] {
        var result: [(Float, Float)] = []
        var start: Float = 0
        for obstacle in obstacles.sorted(by: { $0.center < $1.center }) {
            result.append((start, obstacle.center - obstacle.half))
            start = obstacle.center + obstacle.half
        }
        result.append((start, Self.size))
        return result.filter { $0.0 < $0.1 }
    }

    // MARK: Railway

    private mutating func buildRailway() {
        let (level, size) = (Self.level, Self.size)
        let z = railZ
        for (x0, x1) in stretches(between: alongZ.map { ($0.center, $0.half) }) {
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
        // The rails run unbroken from one end of the town to the other.
        for railZ in [z - 0.625, z + 0.5] {
            box(0, size, level + 0.375, level + 0.625, railZ, railZ + 0.125, Materials.rail)
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
                        guard a0 > 0, a1 < Self.size else { continue }
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

    private mutating func buildBlocks() {
        let xObstacles = alongZ.map { (center: $0.center, half: $0.half) }
        let zObstacles = alongX.map { (center: $0.center, half: $0.half) } + [(railZ, Self.railHalf)]
        for (x0, x1) in stretches(between: xObstacles) where x1 - x0 >= 6 {
            for (z0, z1) in stretches(between: zObstacles) where z1 - z0 >= 6 {
                let block = Rect(x0: x0, z0: z0, x1: x1, z1: z1)
                let roadSides = (
                    west: alongZ.contains { $0.center + $0.half == x0 }, east: alongZ.contains { $0.center - $0.half == x1 },
                    north: alongX.contains { $0.center + $0.half == z0 }, south: alongX.contains { $0.center - $0.half == z1 }
                )
                let largest = random.float(13, 22)
                split(block, largest: largest) { town, lot in
                    town.buildLot(lot, in: block, roadSides: roadSides)
                }
            }
        }
    }

    private mutating func split(_ rect: Rect, largest: Float, _ body: (inout Town, Rect) -> Void) {
        let alongX = rect.width >= rect.depth
        let length = alongX ? rect.width : rect.depth
        guard length > largest, length >= 12 else {
            body(&self, rect)
            return
        }
        let cut = (length * random.float(0.38, 0.62)).rounded()
        if alongX {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x0 + cut, z1: rect.z1), largest: largest, body)
            split(Rect(x0: rect.x0 + cut, z0: rect.z0, x1: rect.x1, z1: rect.z1), largest: largest, body)
        } else {
            split(Rect(x0: rect.x0, z0: rect.z0, x1: rect.x1, z1: rect.z0 + cut), largest: largest, body)
            split(Rect(x0: rect.x0, z0: rect.z0 + cut, x1: rect.x1, z1: rect.z1), largest: largest, body)
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

        // Busier toward where the main street meets the railway.
        let centerX = (lot.x0 + lot.x1) / 2
        let centerZ = (lot.z0 + lot.z1) / 2
        let dx = centerX - 100
        let dz = centerZ - railZ
        let isCentral = (dx * dx + dz * dz).squareRoot() < 62
        plot.build(central: isCentral, random: &random)
        stamp(plot, at: lot, facing: facing)
    }

    /// Copies a plot into the town, turned to face the way it should.
    private mutating func stamp(_ plot: Plot, at lot: Rect, facing: Facing) {
        let (originX, originZ) = (cells(lot.x0), cells(lot.z0))
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
                    grid[originX + worldX, lift + y, originZ + worldZ] = material
                }
            }
        }
        let (width, depth) = (plot.width, plot.depth)
        for lamp in plot.lights {
            var moved = lamp
            let (x, y, z) = (lamp.position.x, lamp.position.y, lamp.position.z)
            let (worldX, worldZ): (Float, Float)
            switch facing {
            case .north: (worldX, worldZ) = (x, z)
            case .south: (worldX, worldZ) = (width - x, depth - z)
            case .west: (worldX, worldZ) = (z, width - x)
            case .east: (worldX, worldZ) = (depth - z, x)
            }
            moved.position = Vector3(lot.x0 + worldX, y + Self.level, lot.z0 + worldZ)
            lights.append(moved)
        }
    }
}
