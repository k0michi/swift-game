import VectorMath

/// What stands on one lot, built facing -z, to be turned to its road: in
/// meters from the lot's corner, with y 0 at the top of the ground.
struct Plot {
    let width: Float
    let depth: Float
    private(set) var grid: VoxelGrid
    private(set) var lights: [PointLight] = []

    // The building's footprint: set back from the road, close at the sides.
    private let left: Float = 0.5
    private var right: Float { width - 0.5 }
    private let front: Float = 1.25
    private var back: Float { depth - 0.5 }
    private var bodyWidth: Float { right - left }
    private var bodyDepth: Float { back - front }

    private static let maximumHeight: Float = 19

    init(width: Float, depth: Float) {
        self.width = width
        self.depth = depth
        // A layer more than the building, below it, for the ground.
        grid = VoxelGrid(width: cells(width), height: cells(Self.maximumHeight) + 1, depth: cells(depth))
    }

    private mutating func box(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float, _ material: UInt8
    ) {
        guard x0 < x1, y0 < y1, z0 < z1 else { return }
        grid.fill(x: x0...x1, y: (y0 + 0.125)...(y1 + 0.125), z: z0...z1, material)
    }

    private mutating func ground(_ material: UInt8) {
        box(0, width, -0.125, 0, 0, depth, material)
    }

    private mutating func light(
        _ x: Float, _ y: Float, _ z: Float, color: UInt32, intensity: Float, radius: Float,
        _ schedule: Material.Schedule = .night
    ) {
        lights.append(
            PointLight(
                position: Vector3(x, y, z), color: Material(color: color).linearColor * intensity, radius: radius,
                schedule: schedule))
    }

    private enum Face: CaseIterable { case front, back, left, right }

    /// Fills a slab on a face of the body: `n` inward from it, `a` along it.
    private mutating func slab(
        _ face: Face, _ n0: Float, _ n1: Float, _ a0: Float, _ a1: Float, _ y0: Float, _ y1: Float, _ material: UInt8
    ) {
        switch face {
        case .front: box(left + a0, left + a1, y0, y1, front + n0, front + n1, material)
        case .back: box(left + a0, left + a1, y0, y1, back - n1, back - n0, material)
        case .left: box(left + n0, left + n1, y0, y1, front + a0, front + a1, material)
        case .right: box(right - n1, right - n0, y0, y1, front + a0, front + a1, material)
        }
    }

    private func length(of face: Face) -> Float {
        face == .front || face == .back ? bodyWidth : bodyDepth
    }

    /// A framed window: glass before a room that is lit at night, or dark.
    private mutating func window(_ face: Face, _ a0: Float, _ a1: Float, _ y0: Float, _ y1: Float, lit: Bool) {
        slab(face, 0, 0.25, a0, a1, y0, y1, Materials.frame)
        slab(face, 0, 0.25, a0 + 0.125, a1 - 0.125, y0 + 0.125, y1 - 0.125, lit ? Materials.roomLight : Materials.frame)
        slab(face, 0, 0.125, a0 + 0.125, a1 - 0.125, y0 + 0.125, y1 - 0.125, Materials.glass)
    }

    private mutating func rowOfWindows(
        _ face: Face, y0: Float, y1: Float, spacing: Float, windowWidth: Float, random: inout SeededRandom
    ) {
        let count = max(Int(length(of: face) / spacing), 1)
        let step = length(of: face) / Float(count)
        for index in 0..<count {
            let middle = step * (Float(index) + 0.5)
            window(face, middle - windowWidth / 2, middle + windowWidth / 2, y0, y1, lit: random.chance(0.45))
        }
    }

    /// Chooses what to build: shops and offices toward the middle of the
    /// town, and homes elsewhere, as far as the lot allows.
    mutating func build(central: Bool, random: inout SeededRandom) {
        let shortest = min(width, depth)
        if shortest < 7 {
            garden(random: &random)
            return
        }
        let roll = random.unit()
        if shortest >= 12 && roll < 0.06 {
            park(random: &random)
        } else if shortest >= 12 && roll < 0.1 {
            shrine()
        } else if shortest >= 10 && roll < 0.17 {
            parking(random: &random)
        } else if central {
            if width >= 12 && depth >= 11 && roll < 0.42 {
                office(random: &random)
            } else if width >= 11 && depth >= 9 && roll < 0.52 {
                convenienceStore(random: &random)
            } else if width >= 8 && depth >= 8 && roll < 0.72 {
                izakaya(random: &random)
            } else {
                shop(random: &random)
            }
        } else if width >= 11 && depth >= 9 && roll < 0.22 {
            convenienceStore(random: &random)
        } else if width >= 10 && depth >= 9 && roll < 0.55 {
            apartment(random: &random)
        } else {
            house(random: &random)
        }
    }

    // MARK: Homes

    private mutating func house(random: inout SeededRandom) {
        ground(Materials.grass)
        let floors = random.int(1, 2)
        let height = Float(floors) * 2.75
        let wall = random.pick([Materials.plaster, Materials.siding, Materials.tileWarm, Materials.brick])
        let roof = random.pick([Materials.roofRed, Materials.roofBlue, Materials.roofBrown, Materials.roof])
        box(left, right, 0, height, front, back, wall)
        for face in Face.allCases {
            for floor in 0..<floors {
                let base = Float(floor) * 2.75
                rowOfWindows(face, y0: base + 1, y1: base + 2.25, spacing: 3.5, windowWidth: 1.25, random: &random)
            }
        }
        let door = bodyWidth / 2
        slab(.front, 0, 0.25, door - 0.5, door + 0.5, 0, 2.125, Materials.wood)
        // A stepped roof, with its ridge along the front.
        var step: Float = 0
        var y = height
        while front + step < back - step {
            box(left, right, y, y + 0.25, front + step, back - step, roof)
            step += 0.375
            y += 0.25
        }
    }

    private mutating func apartment(random: inout SeededRandom) {
        ground(random.chance(0.5) ? Materials.concrete : Materials.grass)
        let floors = random.int(3, 5)
        let height = Float(floors) * 3
        let wall = random.pick([Materials.plaster, Materials.tile, Materials.tileWarm, Materials.concrete])
        box(left, right, 0, height + 0.5, front, back, wall)
        box(left + 0.25, right - 0.25, height + 0.25, height + 0.5, front + 0.25, back - 0.25, Materials.roof)
        let units = max(Int(bodyWidth / 4), 1)
        let unit = bodyWidth / Float(units)
        for floor in 0..<floors {
            let base = Float(floor) * 3
            for face in [Face.left, .right, .back] {
                rowOfWindows(face, y0: base + 0.75, y1: base + 2.25, spacing: 3.5, windowWidth: 1.5, random: &random)
            }
            for index in 0..<units {
                let middle = unit * (Float(index) + 0.5)
                window(.front, middle - 1, middle + 1, base + 0.5, base + 2.5, lit: random.chance(0.45))
                guard floor > 0 else { continue }
                // A balcony reaching toward the road, with railings.
                let (x0, x1) = (left + middle - unit / 2 + 0.125, left + middle + unit / 2 - 0.125)
                box(x0, x1, base - 0.25, base, front - 1, front, Materials.concrete)
                box(x0, x1, base + 0.875, base + 1, front - 1, front - 0.875, Materials.steel)
                var bar = x0
                while bar < x1 {
                    box(bar, bar + 0.125, base, base + 0.875, front - 1, front - 0.875, Materials.steel)
                    bar += 0.25
                }
                if random.chance(0.6) {
                    box(x1 - 0.875, x1 - 0.125, base, base + 0.625, front - 0.5, front - 0.125, Materials.acUnit)
                }
            }
        }
    }

    // MARK: Business

    private mutating func office(random: inout SeededRandom) {
        ground(Materials.concrete)
        let floors = random.int(3, 5)
        let story: Float = 3.5
        let height = Float(floors) * story
        box(left, right, 0, height + 0.5, front, back, Materials.officeWall)
        box(left + 0.25, right - 0.25, height + 0.25, height + 0.5, front + 0.25, back - 0.25, Materials.roof)
        for floor in 0..<floors {
            let base = Float(floor) * story
            for face in Face.allCases {
                let count = max(Int(length(of: face) / 3), 1)
                let step = length(of: face) / Float(count)
                for index in 0..<count where !(floor == 0 && face == .front && index == count / 2) {
                    let a0 = Float(index) * step + 0.125
                    window(face, a0, a0 + step - 0.25, base + 0.625, base + 3, lit: random.chance(0.6))
                }
            }
        }
        let door = (bodyWidth / Float(max(Int(bodyWidth / 3), 1)))
        let middle = bodyWidth / 2
        slab(.front, 0, 0.25, middle - door / 2, middle + door / 2, 0, 3, Materials.frame)
        slab(.front, 0, 0.125, middle - door / 2 + 0.125, middle + door / 2 - 0.125, 0.125, 2.875, Materials.glass)
        slab(.front, 0.125, 0.25, middle - door / 2 + 0.125, middle + door / 2 - 0.125, 0.125, 2.875, Materials.ceilingLight)
        light(left + middle, 2.75, front - 0.75, color: 0xe8f0ff, intensity: 3, radius: 5)
        // Plant on the roof.
        box(left + 1, left + 3, height + 0.5, height + 1.5, front + 1, front + 3, Materials.acUnit)
    }

    private mutating func convenienceStore(random: inout SeededRandom) {
        ground(Materials.concrete)
        let height: Float = 4
        let (band, stripe) = random.pick([
            (Materials.signWhite, Materials.signGreen), (Materials.signWhite, Materials.signBlue),
            (Materials.signWhite, Materials.signOrange),
        ])
        box(left, right, 0, height, front, back, Materials.tile)
        // Hollow, with a floor and strips of light.
        box(left + 0.25, right - 0.25, 0.125, height - 0.25, front, back - 0.25, Materials.air)
        box(left + 0.25, right - 0.25, 0, 0.125, front, back - 0.25, Materials.floorTile)
        box(left, right, height - 0.125, height, front, back, Materials.roof)
        box(left, right, 0.125, 3, front, front + 0.125, Materials.glass)
        var x = left
        while x < right - 0.375 {
            box(x, x + 0.375, 0, 3, front, front + 0.25, Materials.tile)
            x += 3
        }
        box(right - 0.375, right, 0, 3, front, front + 0.25, Materials.tile)
        box(left, right, 3, height - 0.125, front - 0.125, front + 0.25, band)
        box(left, right, 3.25, 3.5, front - 0.125, front, stripe)
        var z = front + 1.5
        while z < back - 0.5 {
            box(left + 1, right - 1, height - 0.5, height - 0.25, z, z + 0.25, Materials.ceilingLight)
            z += 2
        }
        let goods = [Materials.goodsRed, Materials.goodsGreen, Materials.goodsYellow, Materials.goodsBlue]
        z = front + 2
        while z < back - 1.5 {
            box(left + 1.5, right - 1.5, 0.125, 1.5, z, z + 0.5, Materials.shelf)
            var goodsX = left + 1.5
            while goodsX < right - 1.75 {
                box(goodsX, goodsX + 0.25, 0.5, 1.25, z - 0.125, z, random.pick(goods))
                goodsX += 0.375
            }
            z += 2.5
        }
        light(width / 2, height - 0.75, (front + back) / 2, color: 0xf0f4ff, intensity: 7, radius: 8, .always)
    }

    private mutating func izakaya(random: inout SeededRandom) {
        ground(Materials.concrete)
        let height: Float = 6
        box(left, right, 0, height, front, back, Materials.wood)
        box(left - 0.25, right + 0.25, height, height + 0.25, front - 0.5, back, Materials.roofBrown)
        // A lattice of paper, lit from behind, for a door.
        let (x0, x1) = (left + 1, right - 1)
        box(x0, x1, 0.125, 2.5, front, front + 0.25, Materials.paperScreen)
        var x = x0
        while x <= x1 {
            box(x, x + 0.125, 0.125, 2.5, front - 0.0625, front + 0.125, Materials.woodLight)
            x += 0.5
        }
        var y: Float = 0.125
        while y <= 2.5 {
            box(x0, x1, y, y + 0.125, front - 0.0625, front + 0.125, Materials.woodLight)
            y += 0.625
        }
        box(x0, x1, 2, 2.625, front - 0.25, front - 0.125, Materials.noren)
        box(left, right, 2.875, 3.125, front - 1, front, Materials.wood)
        for lantern in [left + 0.25, right - 0.75] {
            box(lantern, lantern + 0.5, 1.875, 2.5, front - 0.75, front - 0.25, Materials.lantern)
            box(lantern + 0.125, lantern + 0.375, 2.5, 2.875, front - 0.625, front - 0.375, Materials.stripeBlack)
            light(lantern + 0.25, 2.2, front - 1.25, color: 0xff3020, intensity: 4, radius: 5)
        }
        rowOfWindows(.front, y0: 3.75, y1: 5.25, spacing: 3, windowWidth: 2, random: &random)
        // A neon sign standing out at the corner.
        let neon = random.chance(0.5)
        let (outer, inner, color): (UInt8, UInt8, UInt32) =
            neon ? (Materials.neonPink, Materials.neonCyan, 0xff3aa8) : (Materials.neonCyan, Materials.neonPink, 0x30e8ff)
        let signX = right - 0.25
        box(signX, signX + 0.25, 3.5, 5.75, front - 1.25, front, Materials.stripeBlack)
        box(signX - 0.125, signX + 0.375, 3.5, 3.625, front - 1.25, front, outer)
        box(signX - 0.125, signX + 0.375, 5.625, 5.75, front - 1.25, front, outer)
        box(signX - 0.125, signX + 0.375, 4, 5.25, front - 1, front - 0.25, inner)
        light(signX - 0.75, 4.5, front - 0.625, color: color, intensity: 4, radius: 6, .always)
    }

    private mutating func shop(random: inout SeededRandom) {
        ground(Materials.sidewalkTile)
        let height: Float = 6
        let wall = random.pick([Materials.plaster, Materials.tileWarm, Materials.siding, Materials.brick])
        box(left, right, 0, height, front, back, wall)
        box(left, right, height - 0.25, height, front, back, Materials.roof)
        // A shopfront lit from within.
        slab(.front, 0, 0.25, 0.25, bodyWidth - 0.25, 0.125, 2.5, Materials.ceilingLight)
        slab(.front, 0, 0.125, 0.25, bodyWidth - 0.25, 0.125, 2.5, Materials.glass)
        let goods = [Materials.goodsRed, Materials.goodsGreen, Materials.goodsYellow, Materials.goodsBlue]
        var along: Float = 0.5
        while along < bodyWidth - 0.75 {
            slab(.front, 0.125, 0.25, along, along + 0.25, 0.25, random.float(0.75, 1.75), random.pick(goods))
            along += 0.375
        }
        // A striped awning, and a sign over it.
        let awning = random.pick([Materials.awningRed, Materials.awningGreen, Materials.awningBlue])
        var x = left
        var striped = false
        while x < right {
            box(x, min(x + 0.5, right), 2.625, 2.875, front - 1, front, striped ? Materials.awningCream : awning)
            x += 0.5
            striped.toggle()
        }
        slab(.front, 0, 0.125, 0.25, bodyWidth - 0.25, 3, 3.5, random.pick([Materials.signWhite, Materials.signRed, Materials.signOrange]))
        rowOfWindows(.front, y0: 4, y1: 5.25, spacing: 3, windowWidth: 1.75, random: &random)
        light(width / 2, 2.25, front - 1, color: 0xffe8c8, intensity: 3, radius: 5)
    }

    // MARK: Open ground

    private mutating func tree(x: Float, z: Float, random: inout SeededRandom) {
        let height = random.float(2, 3.5).rounded()
        box(x, x + 0.25, 0, height, z, z + 0.25, Materials.trunk)
        let leaves = random.chance(0.5) ? Materials.leaves : Materials.leavesLight
        for (rise, reach) in [(Float(0), Float(1)), (0.5, 1.25), (1, 1.25), (1.5, 0.875), (2, 0.5)] {
            box(x + 0.125 - reach, x + 0.125 + reach, height + rise, height + rise + 0.5, z + 0.125 - reach, z + 0.125 + reach, leaves)
        }
    }

    private mutating func garden(random: inout SeededRandom) {
        ground(Materials.grass)
        if min(width, depth) >= 4 {
            tree(x: width / 2, z: depth / 2, random: &random)
        }
    }

    private mutating func park(random: inout SeededRandom) {
        ground(Materials.grass)
        box(width / 2 - 1, width / 2 + 1, -0.125, 0, 0, depth, Materials.gravel)
        box(0, width, -0.125, 0, depth / 2 - 1, depth / 2 + 1, Materials.gravel)
        var z: Float = 2
        while z < depth - 2 {
            var x: Float = 2
            while x < width - 2 {
                let onPath = abs(x - width / 2) < 2.5 || abs(z - depth / 2) < 2.5
                if !onPath && random.chance(0.7) {
                    tree(x: x + random.float(-0.5, 0.5), z: z + random.float(-0.5, 0.5), random: &random)
                }
                x += 4.5
            }
            z += 4.5
        }
        box(width / 2 + 1.25, width / 2 + 2.75, 0, 0.5, depth / 2 + 1.25, depth / 2 + 1.75, Materials.woodLight)
        lampPost(x: width / 2 - 1.5, z: depth / 2 - 1.5)
    }

    private mutating func lampPost(x: Float, z: Float) {
        box(x, x + 0.125, 0, 3.5, z, z + 0.125, Materials.darkSteel)
        box(x - 0.125, x + 0.25, 3.5, 3.75, z - 0.125, z + 0.25, Materials.lampWarm)
        light(x + 0.0625, 3.25, z + 0.0625, color: 0xffd0a0, intensity: 6, radius: 7)
    }

    private mutating func parking(random: inout SeededRandom) {
        ground(Materials.asphaltDark)
        let bay: Float = 2.5
        var x: Float = 0.5
        while x + bay < width - 0.25 {
            box(x, x + 0.125, -0.125, 0, depth - 5.5, depth - 0.5, Materials.lineWhite)
            if random.chance(0.6) {
                let body = random.pick([Materials.carWhite, Materials.carRed, Materials.carBlue, Materials.carBlack])
                let (x0, z0) = (x + 0.5, depth - 5)
                box(x0, x0 + 1.75, 0.25, 1, z0, z0 + 4.25, body)
                box(x0 + 0.125, x0 + 1.625, 1, 1.5, z0 + 1, z0 + 3.25, Materials.glass)
                box(x0 + 0.125, x0 + 1.625, 1.5, 1.625, z0 + 1, z0 + 3.25, body)
            }
            x += bay
        }
        box(x, x + 0.125, -0.125, 0, depth - 5.5, depth - 0.5, Materials.lineWhite)
        lampPost(x: width / 2, z: 1.5)
    }

    private mutating func shrine() {
        ground(Materials.gravel)
        let middle = width / 2
        box(middle - 1, middle + 1, -0.125, 0, 0, depth, Materials.sidewalkTile)
        // A torii over the path.
        for side in [Float(-1.875), 1.625] {
            box(middle + side, middle + side + 0.25, 0, 3.5, 1.5, 1.75, Materials.vermilion)
        }
        box(middle - 2.5, middle + 2.5, 3.5, 3.75, 1.5, 1.75, Materials.vermilion)
        box(middle - 3, middle + 3, 4, 4.25, 1.375, 1.875, Materials.stripeBlack)
        box(middle - 0.125, middle + 0.125, 3.75, 4, 1.5, 1.75, Materials.vermilion)
        // The hall at the back, under a stepped roof.
        let (x0, x1) = (middle - 3, middle + 3)
        let (z0, z1) = (depth - 7, depth - 1)
        box(x0, x1, 0, 0.5, z0, z1, Materials.concrete)
        box(x0 + 0.5, x1 - 0.5, 0.5, 3, z0 + 0.5, z1 - 0.5, Materials.wood)
        box(middle - 1, middle + 1, 0.5, 2.5, z0 + 0.375, z0 + 0.5, Materials.paperScreen)
        var step: Float = 0
        var y: Float = 3
        while z0 - 0.5 + step < z1 + 0.5 - step {
            box(x0 - 0.5, x1 + 0.5, y, y + 0.25, z0 - 0.5 + step, z1 + 0.5 - step, Materials.roofBrown)
            step += 0.5
            y += 0.25
        }
        light(middle, 2.75, z0 - 0.75, color: 0xffd0a0, intensity: 4, radius: 6)
    }
}
