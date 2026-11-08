import VectorMath

/// A lamp that lights what is around it, in its color, and is stopped by
/// what is opaque.
struct PointLight {
    var position: Vector3<Float>
    /// The color in linear light, times how bright it is.
    var color: Vector3<Float>
    /// How far it reaches, in meters.
    var radius: Float
    var schedule: Material.Schedule
}

/// A street corner 40 m square in 1/8 m voxels, for trying out light.
///
/// The ground has two levels: a street at 0.5 m, along which the road runs
/// from west to east, and a terrace 3 m above it to the north, held up by a
/// retaining wall and carrying a railway. A ramp, which crosses the railway
/// at a level crossing, and stairs join them. South of the road stand a
/// convenience store, an apartment building and an izakaya.
struct Scene {
    static let size = (width: Float(40), height: Float(20), depth: Float(40))
    static let streetLevel: Float = 0.5
    /// How wide and deep the generated town is.
    static let townSize: Float = 200
    static let terraceLevel: Float = 3.5
    /// Where the terrace ends, at its retaining wall.
    static let terraceEdge: Float = 12

    /// The voxels and lamps known so far.
    let world: World
    var voxels: SparseVoxels { world.voxels }
    var lights: [PointLight] {
        get { world.lights }
        nonmutating set { world.lights = newValue }
    }
    /// A street corner while it is being built.
    private var grid: VoxelGrid

    /// How wide and deep it is, in meters.
    var width: Float { Float(voxels.width) / Float(voxelsPerMeter) }
    var depth: Float { Float(voxels.depth) / Float(voxelsPerMeter) }

    /// How far along x and z to shift views made for the street corner, to
    /// see the middle of what is built.
    private(set) var middleTileOffset: Float = 0
    /// Where someone on foot starts, along x and z.
    private(set) var spawn = Vector2<Float>(16, 20)

    /// A town laid out from `seed`, 200 m square, with nothing made yet.
    init(townSeed seed: UInt64) {
        let size = cells(Self.townSize)
        world = World(voxels: SparseVoxels(width: size, height: cells(Self.size.height), depth: size), seed: seed)
        grid = VoxelGrid(width: 0, height: 0, depth: 0)
        let halfway = Self.townSize / 2
        spawn = Town.spawn(seed: seed, near: Vector2(halfway, halfway))
        middleTileOffset = halfway - 20
    }

    /// `tiles` by `tiles` copies of the street corner, side by side.
    @MainActor
    init(tiles: Int) async {
        let tile = Scene()
        world = World(voxels: await SparseVoxels(tile: tile.grid, tiles: tiles))
        grid = VoxelGrid(width: 0, height: 0, depth: 0)
        middleTileOffset = Float(tiles / 2) * Self.size.width
        spawn += Vector2(repeating: middleTileOffset)
        for tileZ in 0..<tiles {
            for tileX in 0..<tiles {
                let offset = Vector3<Float>(Float(tileX) * Self.size.width, 0, Float(tileZ) * Self.size.depth)
                for light in tile.lights {
                    var moved = light
                    moved.position = light.position + offset
                    lights.append(moved)
                }
            }
        }
    }

    private init() {
        world = World(voxels: SparseVoxels())
        grid = VoxelGrid(
            width: cells(Self.size.width), height: cells(Self.size.height), depth: cells(Self.size.depth))
        buildGround()
        buildRamp()
        buildStairs()
        buildRailway()
        buildLevelCrossing()
        buildTerraceEdge()
        buildRoad()
        buildStreetLamps()
        buildVendingMachines()
        buildTrafficSignal()
        buildConvenienceStore()
        buildApartment()
        buildIzakaya()
    }

    // MARK: Helpers

    /// Fills the box from (x0, y0, z0) to (x1, y1, z1), in meters.
    private mutating func box(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float, _ material: UInt8
    ) {
        grid.fill(x: x0...x1, y: y0...y1, z: z0...z1, material)
    }

    private mutating func light(
        _ x: Float, _ y: Float, _ z: Float, color: UInt32, intensity: Float, radius: Float,
        _ schedule: Material.Schedule = .always
    ) {
        let linear = Material(color: color).linearColor
        lights.append(
            PointLight(position: Vector3(x, y, z), color: linear * intensity, radius: radius, schedule: schedule))
    }

    // MARK: Ground

    private mutating func buildGround() {
        let width = Self.size.width
        // The street level, and the terrace behind its wall.
        box(0, width, 0, Self.streetLevel, 0, Self.size.depth, Materials.soil)
        box(0, width, 0, Self.terraceLevel, 0, Self.terraceEdge, Materials.concrete)
        box(0, width, Self.terraceLevel - 0.125, Self.terraceLevel, 0, Self.terraceEdge, Materials.grass)
        // A plaza of tiles between the wall and the sidewalk.
        box(0, width, Self.streetLevel - 0.125, Self.streetLevel, Self.terraceEdge, 22, Materials.sidewalkTile)
        // A gutter along the foot of the wall.
        box(0, width, Self.streetLevel - 0.125, Self.streetLevel, Self.terraceEdge, 12.25, Materials.concreteDark)
        // The lots south of the road.
        box(0, width, Self.streetLevel - 0.125, Self.streetLevel, 33, Self.size.depth, Materials.concrete)
    }

    /// A ramp from the street up to the terrace, 6 m wide, rising 3 m over
    /// 12 m in steps of a voxel.
    private mutating func buildRamp() {
        let (x0, x1): (Float, Float) = (2, 8)
        let start = Self.terraceEdge
        let length: Float = 12
        for z in cells(start)..<cells(start + length) {
            let along = (Float(z) / Float(voxelsPerMeter) - start) / length
            let top = cells(Self.terraceLevel - (Self.terraceLevel - Self.streetLevel) * along)
            grid.fill(x: cells(x0)..<cells(x1), y: 0..<(top - 1), z: z..<(z + 1), Materials.concrete)
            grid.fill(x: cells(x0)..<cells(x1), y: (top - 1)..<top, z: z..<(z + 1), Materials.asphalt)
            // Low walls on both sides.
            for x in [cells(x0) - 2, cells(x1)] {
                grid.fill(x: x..<(x + 2), y: 0..<(top + 5), z: z..<(z + 1), Materials.concrete)
            }
        }
        // The road on the terrace, north to the edge of the scene.
        box(x0, x1, Self.terraceLevel - 0.125, Self.terraceLevel, 0, start, Materials.asphalt)
        box(x0 + 2.875, x0 + 3.125, Self.terraceLevel - 0.125, Self.terraceLevel, 0, start, Materials.lineYellow)
    }

    /// Stairs from the plaza up to the terrace: twelve steps of a 0.25 m
    /// rise and a 0.375 m tread, with handrails.
    private mutating func buildStairs() {
        let (x0, x1): (Float, Float) = (20, 22.5)
        let rise: Float = 0.25
        let tread: Float = 0.375
        for step in 0..<12 {
            let z0 = Self.terraceEdge + tread * Float(step)
            let top = Self.terraceLevel - rise * Float(step + 1)
            box(x0, x1, 0, top, z0, z0 + tread, Materials.concrete)
            // A dark nosing on each step.
            box(x0, x1, top - 0.125, top, z0 + tread - 0.125, z0 + tread, Materials.concreteDark)
        }
        // Handrails on posts, following the steps.
        for x in [x0 - 0.125, x1] {
            for step in stride(from: 0, to: 12, by: 3) {
                let z = Self.terraceEdge + tread * Float(step) + 0.125
                let top = Self.terraceLevel - rise * Float(step + 1)
                box(x, x + 0.125, top - 0.25, top + 0.875, z, z + 0.125, Materials.steel)
            }
            for step in 0..<12 {
                let z0 = Self.terraceEdge + tread * Float(step)
                let top = Self.terraceLevel - rise * Float(step + 1)
                box(x, x + 0.125, top + 0.875, top + 1, z0, z0 + tread, Materials.steel)
            }
        }
    }

    // MARK: Railway

    /// A single track on ballast along the terrace, its rails 1.125 m apart,
    /// center to center.
    private mutating func buildRailway() {
        let width = Self.size.width
        let base = Self.terraceLevel
        box(0, width, base, base + 0.125, 2.5, 9.5, Materials.ballast)
        box(0, width, base + 0.125, base + 0.25, 3, 9, Materials.ballast)
        // Sleepers every 0.625 m.
        var x: Float = 0.25
        while x < width {
            box(x, x + 0.25, base + 0.25, base + 0.375, 5, 7, Materials.sleeper)
            x += 0.625
        }
        for z in [Float(5.375), 6.5] {
            box(0, width, base + 0.375, base + 0.625, z, z + 0.125, Materials.rail)
        }
    }

    /// Where the ramp's road crosses the railway: a deck flush with the
    /// rails' feet, and crossing signals with two lamps that take turns.
    private mutating func buildLevelCrossing() {
        let base = Self.terraceLevel
        let (x0, x1): (Float, Float) = (2, 8)
        box(x0, x1, base, base + 0.125, 2.5, 9.5, Materials.asphalt)
        box(x0, x1, base + 0.125, base + 0.25, 3, 9, Materials.asphalt)
        box(x0, x1, base + 0.25, base + 0.375, 4, 8, Materials.crossingDeck)
        // The rails run on through the deck.
        for z in [Float(5.375), 6.5] {
            box(x0, x1, base + 0.375, base + 0.5, z, z + 0.125, Materials.rail)
        }

        // A signal on each side, facing the road both ways.
        for (x, z) in [(Float(1.25), Float(2.0)), (Float(8.5), Float(9.75))] {
            // A pole striped yellow and black.
            var y = base
            var stripe = false
            while y < base + 2.5 {
                box(x, x + 0.25, y, y + 0.25, z, z + 0.25, stripe ? Materials.stripeBlack : Materials.stripeYellow)
                y += 0.25
                stripe.toggle()
            }
            box(x, x + 0.25, base + 2.5, base + 3.25, z, z + 0.25, Materials.darkSteel)
            // A crossbuck, flat across the road.
            box(x - 0.5, x + 0.75, base + 3.0, base + 3.125, z + 0.25, z + 0.375, Materials.stripeYellow)
            // Two lamps, one each side of the pole, facing north and south.
            for (offset, lamp, schedule) in [
                (Float(-0.5), Materials.crossingLampA, Material.Schedule.blinkA),
                (Float(0.5), Materials.crossingLampB, Material.Schedule.blinkB),
            ] {
                let lx = x + offset
                box(lx, lx + 0.25, base + 2.25, base + 2.625, z - 0.125, z + 0.375, Materials.stripeBlack)
                box(lx, lx + 0.25, base + 2.25, base + 2.5, z - 0.25, z - 0.125, lamp)
                box(lx, lx + 0.25, base + 2.25, base + 2.5, z + 0.375, z + 0.5, lamp)
                light(lx + 0.125, base + 2.375, z - 0.5, color: 0xff2a1a, intensity: 6, radius: 5, schedule)
                light(lx + 0.125, base + 2.375, z + 0.75, color: 0xff2a1a, intensity: 6, radius: 5, schedule)
            }
        }
    }

    /// A fence along the top of the retaining wall, and utility poles.
    private mutating func buildTerraceEdge() {
        let base = Self.terraceLevel
        let z = Self.terraceEdge - 0.25
        var x: Float = 0
        while x < Self.size.width {
            let inRoad = x >= 1.5 && x < 8.5
            let onStairs = x >= 19.75 && x < 22.75
            if !inRoad && !onStairs {
                if Int(x * 8) % 16 == 0 {
                    box(x, x + 0.125, base, base + 1.25, z, z + 0.125, Materials.darkSteel)
                }
                box(x, x + 0.125, base + 1.125, base + 1.25, z, z + 0.125, Materials.darkSteel)
                box(x, x + 0.125, base + 0.5, base + 0.625, z, z + 0.125, Materials.darkSteel)
            }
            x += 0.125
        }
        // Concrete utility poles, 9 m tall, with crossarms.
        for px in [Float(14), 30] {
            box(px, px + 0.375, base, base + 9, 10.75, 11.125, Materials.poleConcrete)
            box(px - 0.75, px + 1.125, base + 8.25, base + 8.375, 10.75, 11.125, Materials.darkSteel)
            box(px - 0.75, px + 1.125, base + 7.5, base + 7.625, 10.75, 11.125, Materials.darkSteel)
            // A transformer on one.
            if px == 30 {
                box(px + 0.375, px + 1.0, base + 5.5, base + 6.5, 10.625, 11.25, Materials.steel)
            }
        }
    }

    // MARK: Road

    /// A road along x, a lane each way, with raised sidewalks and a zebra
    /// crossing.
    private mutating func buildRoad() {
        let width = Self.size.width
        let level = Self.streetLevel
        // Sidewalks a curb's height, 0.125 m, above the road.
        for (z0, z1, curbZ) in [(Float(22), Float(24), Float(23.875)), (Float(31), Float(33), Float(31))] {
            box(0, width, level, level + 0.125, z0, z1, Materials.sidewalk)
            box(0, width, level, level + 0.125, curbZ, curbZ + 0.125, Materials.curb)
        }
        box(0, width, level - 0.125, level, 24, 31, Materials.asphalt)
        // Lines: white along the edges, yellow down the middle.
        box(0, width, level - 0.125, level, 24.375, 24.5, Materials.lineWhite)
        box(0, width, level - 0.125, level, 30.5, 30.625, Materials.lineWhite)
        box(0, width, level - 0.125, level, 27.5, 27.625, Materials.lineYellow)
        // The zebra crossing, in stripes 0.5 m wide.
        var x: Float = 22
        while x < 26 {
            box(x, x + 0.5, level - 0.125, level, 24.75, 30.25, Materials.lineWhite)
            box(x + 0.5, x + 1, level - 0.125, level, 24.75, 30.25, Materials.asphalt)
            x += 1
        }
        // Where the ramp meets the road, the sidewalk dips.
        box(2, 8, level, level + 0.125, 22, 24, Materials.air)
        box(2, 8, level - 0.125, level, 22, 24, Materials.asphaltDark)
        // A manhole.
        box(14, 14.625, level - 0.125, level, 27.875, 28.5, Materials.darkSteel)
    }

    /// Street lamps on the north sidewalk, reaching over the road.
    private mutating func buildStreetLamps() {
        let level = Self.streetLevel + 0.125
        for x in [Float(11), 27, 37] {
            box(x, x + 0.25, level, level + 6, 23.375, 23.625, Materials.darkSteel)
            box(x, x + 0.25, level + 5.75, level + 6, 23.625, 25, Materials.darkSteel)
            box(x - 0.125, x + 0.375, level + 5.625, level + 5.875, 24.5, 25.25, Materials.darkSteel)
            box(x - 0.125, x + 0.375, level + 5.5, level + 5.625, 24.5, 25.25, Materials.lampWarm)
            light(x + 0.125, level + 5.25, 24.875, color: 0xffc890, intensity: 14, radius: 11, .night)
        }
    }

    /// Two vending machines against the retaining wall, lit from inside.
    private mutating func buildVendingMachines() {
        let level = Self.streetLevel
        let z0 = Self.terraceEdge + 0.25
        let z1 = z0 + 0.75
        for (x, body) in [(Float(12), Materials.vendingRed), (Float(13.125), Materials.vendingBlue)] {
            box(x, x + 1, level, level + 1.875, z0, z1, body)
            // The display of drinks, the buttons under it and the slot.
            box(x + 0.125, x + 0.875, level + 1.0, level + 1.625, z1 - 0.125, z1, Materials.vendingPanel)
            box(x + 0.125, x + 0.875, level + 0.875, level + 1.0, z1 - 0.125, z1, Materials.vendingButton)
            box(x + 0.125, x + 0.875, level + 0.125, level + 0.375, z1 - 0.125, z1, Materials.stripeBlack)
            light(x + 0.5, level + 1.3, z1 + 0.375, color: 0xe8f0ff, intensity: 3, radius: 4)
        }
    }

    /// A traffic signal over the road at the crossing, facing the traffic
    /// both ways.
    private mutating func buildTrafficSignal() {
        let level = Self.streetLevel + 0.125
        let x: Float = 21
        box(x, x + 0.25, level, level + 5.5, 31.5, 31.75, Materials.darkSteel)
        box(x, x + 0.25, level + 5.25, level + 5.5, 28.5, 31.5, Materials.darkSteel)
        box(x - 0.125, x + 0.375, level + 4.75, level + 5.25, 27, 28.875, Materials.darkSteel)
        let lamps: [(Float, UInt8, Material.Schedule, UInt32)] = [
            (27.125, Materials.signalGreen, .signalGreen, 0x1affb0),
            (27.75, Materials.signalYellow, .signalYellow, 0xffb21a),
            (28.375, Materials.signalRed, .signalRed, 0xff2a1a),
        ]
        for (z, lamp, schedule, color) in lamps {
            box(x - 0.25, x - 0.125, level + 4.875, level + 5.125, z, z + 0.375, lamp)
            box(x + 0.375, x + 0.5, level + 4.875, level + 5.125, z, z + 0.375, lamp)
            light(x - 0.5, level + 5.0, z + 0.1875, color: color, intensity: 3, radius: 4, schedule)
            light(x + 0.75, level + 5.0, z + 0.1875, color: color, intensity: 3, radius: 4, schedule)
        }
    }

    // MARK: Buildings

    /// A convenience store: a glass front under a lit sign band, and
    /// shelves under bright ceiling lights inside.
    private mutating func buildConvenienceStore() {
        let level = Self.streetLevel
        let (x0, x1): (Float, Float) = (1.5, 13.5)
        let (z0, z1): (Float, Float) = (33.5, 39.5)
        let top = level + 4.25
        // Walls, floor and roof.
        box(x0, x1, level, top, z0, z1, Materials.tile)
        box(x0 + 0.25, x1 - 0.25, level + 0.125, top - 0.25, z0, z1 - 0.25, Materials.air)
        box(x0 + 0.25, x1 - 0.25, level, level + 0.125, z0, z1 - 0.25, Materials.floorTile)
        box(x0 + 0.25, x1 - 0.25, level + 0.125, top - 0.25, z1 - 0.375, z1 - 0.25, Materials.interiorWall)
        box(x0, x1, top - 0.125, top, z0, z1, Materials.roof)
        // The front: glass between pillars every 3 m, under the sign.
        box(x0, x1, level + 0.125, level + 3.25, z0, z0 + 0.125, Materials.glass)
        var x = x0
        while x <= x1 - 0.375 {
            box(x, x + 0.375, level, level + 3.25, z0, z0 + 0.25, Materials.tile)
            x += 3
        }
        box(x1 - 0.375, x1, level, level + 3.25, z0, z0 + 0.25, Materials.tile)
        box(x0, x1, level + 3.25, top - 0.125, z0 - 0.125, z0 + 0.25, Materials.signWhite)
        box(x0, x1, level + 3.5, level + 3.625, z0 - 0.125, z0, Materials.signGreen)
        box(x0, x1, level + 3.75, level + 3.875, z0 - 0.125, z0, Materials.signBlue)
        // Ceiling lights in strips.
        for z in [Float(35), 36.75, 38.5] {
            box(x0 + 1, x1 - 1, top - 0.375, top - 0.25, z, z + 0.25, Materials.ceilingLight)
        }
        // Shelves with goods, and a counter.
        let goods = [Materials.goodsRed, Materials.goodsGreen, Materials.goodsYellow, Materials.goodsBlue]
        for (row, z) in [Float(35.75), 37.5].enumerated() {
            box(4, 12, level + 0.125, level + 1.625, z, z + 0.5, Materials.shelf)
            var gx: Float = 4
            var index = row
            while gx < 12 {
                for shelfY in [Float(0.375), 0.875, 1.375] {
                    box(gx, gx + 0.25, level + shelfY, level + shelfY + 0.25, z - 0.125, z, goods[index % 4])
                    box(gx, gx + 0.25, level + shelfY, level + shelfY + 0.25, z + 0.5, z + 0.625, goods[(index + 1) % 4])
                }
                gx += 0.375
                index += 1
            }
        }
        box(1.75, 3.25, level + 0.125, level + 1.125, 35, 38, Materials.woodLight)
        for lx in [Float(4), 7.5, 11] {
            light(lx, top - 0.75, 36.5, color: 0xf0f4ff, intensity: 7, radius: 8)
        }
    }

    /// Four floors of flats, with framed windows and balconies, some rooms
    /// lit at night.
    private mutating func buildApartment() {
        let level = Self.streetLevel
        let (x0, x1): (Float, Float) = (15.5, 27.5)
        let (z0, z1): (Float, Float) = (34.5, 39.75)
        let floorHeight: Float = 3
        let floors = 4
        let top = level + floorHeight * Float(floors) + 0.5
        box(x0, x1, level, top, z0, z1, Materials.plaster)
        // Rooms: hollow, floor by floor and flat by flat.
        let units: [Float] = [17.5, 21.5, 25.5]
        let lit: Set<Int> = [0, 2, 4, 7, 9, 11]
        for floor in 0..<floors {
            let base = level + floorHeight * Float(floor) + 0.25
            for (unit, cx) in units.enumerated() {
                box(cx - 1.75, cx + 1.75, base, base + 2.5, z0 + 0.25, z1 - 0.375, Materials.air)
                box(cx - 1.75, cx + 1.75, base - 0.125, base, z0 + 0.25, z1 - 0.375, Materials.floorWood)
                box(cx - 1.75, cx + 1.75, base, base + 2.5, z1 - 0.5, z1 - 0.375, Materials.interiorWall)
                // A window, framed, with a mullion.
                box(cx - 1, cx + 1, base + 0.5, base + 2.25, z0, z0 + 0.25, Materials.frame)
                box(cx - 0.875, cx + 0.875, base + 0.625, base + 2.125, z0, z0 + 0.25, Materials.air)
                box(cx - 0.875, cx + 0.875, base + 0.625, base + 2.125, z0 + 0.0625, z0 + 0.1875, Materials.glass)
                box(cx - 0.0625, cx + 0.0625, base + 0.625, base + 2.125, z0 + 0.0625, z0 + 0.1875, Materials.frame)
                if lit.contains(floor * units.count + unit) {
                    box(cx - 0.375, cx + 0.375, base + 2.375, base + 2.5, 36.5, 37.25, Materials.roomLight)
                    light(cx, base + 2.0, 36.25, color: 0xffd8a8, intensity: 5, radius: 6, .night)
                }
                // A balcony with railings, and an air conditioner on it.
                if floor > 0 {
                    box(cx - 1.75, cx + 1.75, base - 0.375, base, z0 - 1.25, z0, Materials.concrete)
                    box(cx - 1.75, cx + 1.75, base + 0.875, base + 1.0, z0 - 1.25, z0 - 1.125, Materials.steel)
                    var bx = cx - 1.75
                    while bx < cx + 1.75 {
                        box(bx, bx + 0.125, base, base + 0.875, z0 - 1.25, z0 - 1.125, Materials.steel)
                        bx += 0.25
                    }
                    box(cx + 0.75, cx + 1.5, base, base + 0.625, z0 - 0.5, z0 - 0.125, Materials.acUnit)
                }
            }
        }
        // The entrance, with a glass door and a light over it.
        box(20.75, 22.25, level, level + 2.25, z0, z0 + 0.25, Materials.frame)
        box(20.875, 22.125, level + 0.125, level + 2.125, z0, z0 + 0.25, Materials.glass)
        box(20.5, 22.5, level + 2.375, level + 2.5, z0 - 0.75, z0, Materials.concrete)
        box(21.25, 21.75, level + 2.25, level + 2.375, z0 - 0.5, z0 - 0.25, Materials.lampCool)
        light(21.5, level + 2.0, z0 - 0.5, color: 0xe8f0ff, intensity: 3, radius: 5, .night)
        // A parapet, and a water tank on the roof.
        box(x0 + 0.25, x1 - 0.25, top - 0.375, top, z0 + 0.25, z1 - 0.25, Materials.air)
        box(x0 + 0.25, x1 - 0.25, top - 0.5, top - 0.375, z0 + 0.25, z1 - 0.25, Materials.roof)
        box(24, 26, top - 0.375, top + 1.25, 36, 38, Materials.steel)
    }

    /// A two-story izakaya of dark wood: lattice doors glowing with paper,
    /// red lanterns, a curtain over the door, and a neon sign.
    private mutating func buildIzakaya() {
        let level = Self.streetLevel
        let (x0, x1): (Float, Float) = (29.5, 39.5)
        let (z0, z1): (Float, Float) = (33.5, 39.75)
        let top = level + 6.5
        box(x0, x1, level, top, z0, z1, Materials.wood)
        box(x0 + 0.25, x1 - 0.25, level + 0.125, level + 2.75, z0 + 0.25, z1 - 0.25, Materials.air)
        box(x0 + 0.25, x1 - 0.25, level, level + 0.125, z0 + 0.25, z1 - 0.25, Materials.floorWood)
        box(x0 + 0.25, x1 - 0.25, level + 3.25, level + 6.0, z0 + 0.25, z1 - 0.25, Materials.air)
        box(x0 + 0.25, x1 - 0.25, level + 3.125, level + 3.25, z0 + 0.25, z1 - 0.25, Materials.floorWood)
        // Lattice doors: a grid of wood with glowing paper between.
        box(31, 36, level + 0.125, level + 2.5, z0, z0 + 0.25, Materials.paperScreen)
        var lx: Float = 31
        while lx <= 36 {
            box(lx, lx + 0.125, level + 0.125, level + 2.5, z0 - 0.0625, z0 + 0.125, Materials.woodLight)
            lx += 0.5
        }
        var ly = level + 0.125
        while ly <= level + 2.5 {
            box(31, 36.125, ly, ly + 0.125, z0 - 0.0625, z0 + 0.125, Materials.woodLight)
            ly += 0.625
        }
        light(33.5, level + 1.5, z0 + 1.5, color: 0xffd0a0, intensity: 6, radius: 7, .night)
        // A curtain over the door, in three panels.
        for panel in 0..<3 {
            let px = 32 + Float(panel) * 1.0
            box(px, px + 0.875, level + 2.0, level + 2.625, z0 - 0.25, z0 - 0.125, Materials.noren)
        }
        // The eave, and red lanterns hanging from it.
        box(x0 - 0.25, x1 + 0.25, level + 2.875, level + 3.125, z0 - 1.0, z0, Materials.wood)
        for x in [Float(30.25), 37.25] {
            box(x, x + 0.5, level + 1.875, level + 2.5, z0 - 0.75, z0 - 0.25, Materials.lantern)
            box(x + 0.125, x + 0.375, level + 2.5, level + 2.875, z0 - 0.625, z0 - 0.375, Materials.stripeBlack)
            light(x + 0.25, level + 2.2, z0 - 1.25, color: 0xff3020, intensity: 4, radius: 5, .night)
        }
        // Upstairs windows with paper behind glass.
        for x in [Float(30.5), 33.5, 36.5] {
            box(x, x + 2, level + 3.875, level + 5.375, z0, z0 + 0.25, Materials.woodLight)
            box(x + 0.125, x + 1.875, level + 4.0, level + 5.25, z0, z0 + 0.125, Materials.glass)
            box(x + 0.125, x + 1.875, level + 4.0, level + 5.25, z0 + 0.125, z0 + 0.25, Materials.paperScreen)
        }
        light(34.5, level + 4.75, z0 + 1.0, color: 0xffd0a0, intensity: 4, radius: 6, .night)
        // A roof of dark tiles.
        box(x0 - 0.25, x1 + 0.25, top, top + 0.25, z0 - 0.5, z1, Materials.roof)
        // A neon sign standing out from the corner: a pink frame around
        // cyan bars.
        let (sx, sz0, sz1): (Float, Float, Float) = (38.75, 32.0, 33.5)
        box(sx, sx + 0.25, level + 3.5, level + 6.25, sz0, sz1, Materials.stripeBlack)
        for side in [sx - 0.125, sx + 0.25] {
            box(side, side + 0.125, level + 3.5, level + 3.625, sz0, sz1, Materials.neonPink)
            box(side, side + 0.125, level + 6.125, level + 6.25, sz0, sz1, Materials.neonPink)
            box(side, side + 0.125, level + 3.5, level + 6.25, sz0, sz0 + 0.125, Materials.neonPink)
            box(side, side + 0.125, level + 3.5, level + 6.25, sz1 - 0.125, sz1, Materials.neonPink)
            for (y0, y1) in [(Float(3.875), Float(4.5)), (4.875, 5.5), (5.75, 5.875)] {
                box(side, side + 0.125, level + y0, level + y1, sz0 + 0.375, sz1 - 0.375, Materials.neonCyan)
            }
        }
        light(sx - 0.75, level + 4.75, 32.75, color: 0xff3aa8, intensity: 4, radius: 6)
        light(sx + 1.0, level + 4.75, 32.75, color: 0x30e8ff, intensity: 3, radius: 5)
    }
}
