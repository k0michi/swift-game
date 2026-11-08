import RealModule
import VectorMath

/// What a voxel is made of: its color, whether light passes through it, and
/// whether and when it glows.
struct Material {
    enum Kind: Int {
        case opaque = 0
        /// Lets light through, drawn after everything opaque.
        case glass = 1
    }

    /// When a material glows, or a lamp shines.
    enum Schedule: Int {
        case always = 0
        /// From dusk to dawn.
        case night = 1
        /// Railway crossing lamps, which take turns.
        case blinkA = 2
        case blinkB = 3
        /// The traffic signal's three colors, one at a time.
        case signalRed = 4
        case signalYellow = 5
        case signalGreen = 6
    }

    /// The color, as 0xRRGGBB in sRGB.
    var color: UInt32
    var kind = Kind.opaque
    /// How bright it glows, over its color: 0 for not at all.
    var emission: Float = 0
    var schedule = Schedule.always
    /// From 0, a mirror, to 1, matte; for highlights.
    var roughness: Float = 0.9
    /// How far each voxel's brightness strays from the color, as a fraction
    /// of it, at most either way.
    var variation: Float = 0
    /// How far each voxel's red, green and blue stray apart, in the same way.
    var hueVariation: Float = 0

    /// The color in linear light, from 0 to 1.
    var linearColor: Vector3<Float> {
        func channel(_ shift: UInt32) -> Float {
            let value = Float((color >> shift) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : Float.pow((value + 0.055) / 1.055, 2.4)
        }
        return Vector3(channel(16), channel(8), channel(0))
    }
}

/// The materials, by palette index; index 0 is air.
enum Materials {
    /// The materials' palette indices, in the order of `table`.
    enum ID: UInt8, CaseIterable {
        case air
        case soil
        case asphalt
        case asphaltDark
        case lineWhite
        case lineYellow
        case sidewalk
        case sidewalkTile
        case curb
        case concrete
        case concreteDark
        case grass
        case ballast
        case sleeper
        case rail
        case crossingDeck
        case steel
        case darkSteel
        case poleConcrete
        case stripeYellow
        case stripeBlack
        case lampWarm
        case lampCool
        case crossingLampA
        case crossingLampB
        case signalRed
        case signalYellow
        case signalGreen
        case vendingRed
        case vendingBlue
        case vendingPanel
        case vendingButton
        case tile
        case tileWarm
        case plaster
        case frame
        case wood
        case woodLight
        case floorWood
        case floorTile
        case interiorWall
        case shelf
        case goodsRed
        case goodsGreen
        case goodsYellow
        case goodsBlue
        case roof
        case acUnit
        case glass
        case ceilingLight
        case roomLight
        case signWhite
        case signGreen
        case signBlue
        case lantern
        case paperScreen
        case neonPink
        case neonCyan
        case noren
        case roofRed
        case roofBlue
        case roofBrown
        case brick
        case siding
        case officeWall
        case awningRed
        case awningGreen
        case awningBlue
        case awningCream
        case signOrange
        case signRed
        case trunk
        case leaves
        case leavesLight
        case gravel
        case vermilion
        case carWhite
        case carRed
        case carBlue
        case carBlack
        case skin
        case hair
        case shirt
        case jacket
        case trousers
        case shoes
        case bag
    }

    static let air = ID.air.rawValue
    static let soil = ID.soil.rawValue
    static let asphalt = ID.asphalt.rawValue
    static let asphaltDark = ID.asphaltDark.rawValue
    static let lineWhite = ID.lineWhite.rawValue
    static let lineYellow = ID.lineYellow.rawValue
    static let sidewalk = ID.sidewalk.rawValue
    static let sidewalkTile = ID.sidewalkTile.rawValue
    static let curb = ID.curb.rawValue
    static let concrete = ID.concrete.rawValue
    static let concreteDark = ID.concreteDark.rawValue
    static let grass = ID.grass.rawValue
    static let ballast = ID.ballast.rawValue
    static let sleeper = ID.sleeper.rawValue
    static let rail = ID.rail.rawValue
    static let crossingDeck = ID.crossingDeck.rawValue
    static let steel = ID.steel.rawValue
    static let darkSteel = ID.darkSteel.rawValue
    static let poleConcrete = ID.poleConcrete.rawValue
    static let stripeYellow = ID.stripeYellow.rawValue
    static let stripeBlack = ID.stripeBlack.rawValue
    static let lampWarm = ID.lampWarm.rawValue
    static let lampCool = ID.lampCool.rawValue
    static let crossingLampA = ID.crossingLampA.rawValue
    static let crossingLampB = ID.crossingLampB.rawValue
    static let signalRed = ID.signalRed.rawValue
    static let signalYellow = ID.signalYellow.rawValue
    static let signalGreen = ID.signalGreen.rawValue
    static let vendingRed = ID.vendingRed.rawValue
    static let vendingBlue = ID.vendingBlue.rawValue
    static let vendingPanel = ID.vendingPanel.rawValue
    static let vendingButton = ID.vendingButton.rawValue
    static let tile = ID.tile.rawValue
    static let tileWarm = ID.tileWarm.rawValue
    static let plaster = ID.plaster.rawValue
    static let frame = ID.frame.rawValue
    static let wood = ID.wood.rawValue
    static let woodLight = ID.woodLight.rawValue
    static let floorWood = ID.floorWood.rawValue
    static let floorTile = ID.floorTile.rawValue
    static let interiorWall = ID.interiorWall.rawValue
    static let shelf = ID.shelf.rawValue
    static let goodsRed = ID.goodsRed.rawValue
    static let goodsGreen = ID.goodsGreen.rawValue
    static let goodsYellow = ID.goodsYellow.rawValue
    static let goodsBlue = ID.goodsBlue.rawValue
    static let roof = ID.roof.rawValue
    static let acUnit = ID.acUnit.rawValue
    static let glass = ID.glass.rawValue
    static let ceilingLight = ID.ceilingLight.rawValue
    static let roomLight = ID.roomLight.rawValue
    static let signWhite = ID.signWhite.rawValue
    static let signGreen = ID.signGreen.rawValue
    static let signBlue = ID.signBlue.rawValue
    static let lantern = ID.lantern.rawValue
    static let paperScreen = ID.paperScreen.rawValue
    static let neonPink = ID.neonPink.rawValue
    static let neonCyan = ID.neonCyan.rawValue
    static let noren = ID.noren.rawValue
    static let roofRed = ID.roofRed.rawValue
    static let roofBlue = ID.roofBlue.rawValue
    static let roofBrown = ID.roofBrown.rawValue
    static let brick = ID.brick.rawValue
    static let siding = ID.siding.rawValue
    static let officeWall = ID.officeWall.rawValue
    static let awningRed = ID.awningRed.rawValue
    static let awningGreen = ID.awningGreen.rawValue
    static let awningBlue = ID.awningBlue.rawValue
    static let awningCream = ID.awningCream.rawValue
    static let signOrange = ID.signOrange.rawValue
    static let signRed = ID.signRed.rawValue
    static let trunk = ID.trunk.rawValue
    static let leaves = ID.leaves.rawValue
    static let leavesLight = ID.leavesLight.rawValue
    static let gravel = ID.gravel.rawValue
    static let vermilion = ID.vermilion.rawValue
    static let carWhite = ID.carWhite.rawValue
    static let carRed = ID.carRed.rawValue
    static let carBlue = ID.carBlue.rawValue
    static let carBlack = ID.carBlack.rawValue
    static let skin = ID.skin.rawValue
    static let hair = ID.hair.rawValue
    static let shirt = ID.shirt.rawValue
    static let jacket = ID.jacket.rawValue
    static let trousers = ID.trousers.rawValue
    static let shoes = ID.shoes.rawValue
    static let bag = ID.bag.rawValue

    /// Each material, by palette index.
    static let table: [Material] = ID.allCases.map(material)

    private static func material(_ id: ID) -> Material {
        switch id {
        case .air: Material(color: 0)
        case .soil: Material(color: 0x6b5a48, variation: 0.22, hueVariation: 0.06)
        case .asphalt: Material(color: 0x3b3e43, roughness: 0.8, variation: 0.2, hueVariation: 0.02)
        case .asphaltDark: Material(color: 0x33363a, roughness: 0.8, variation: 0.2, hueVariation: 0.02)
        case .lineWhite: Material(color: 0xe6e3da, variation: 0.06)
        case .lineYellow: Material(color: 0xd8a930, variation: 0.08, hueVariation: 0.02)
        case .sidewalk: Material(color: 0xa7a296, variation: 0.09, hueVariation: 0.02)
        case .sidewalkTile: Material(color: 0x958f84, variation: 0.09, hueVariation: 0.02)
        case .curb: Material(color: 0xc4c0b6, variation: 0.07, hueVariation: 0.01)
        case .concrete: Material(color: 0x9a9b98, variation: 0.1, hueVariation: 0.01)
        case .concreteDark: Material(color: 0x77797a, variation: 0.12, hueVariation: 0.01)
        case .grass: Material(color: 0x5e8a3a, variation: 0.28, hueVariation: 0.12)
        case .ballast: Material(color: 0x7d7a74, variation: 0.35, hueVariation: 0.04)
        case .sleeper: Material(color: 0x8c8a84, variation: 0.12, hueVariation: 0.02)
        case .rail: Material(color: 0x6a6460, roughness: 0.35, variation: 0.06)
        case .crossingDeck: Material(color: 0x2d2d2f, variation: 0.12)
        case .steel: Material(color: 0x8f969c, roughness: 0.5, variation: 0.04)
        case .darkSteel: Material(color: 0x464b50, roughness: 0.5, variation: 0.05)
        case .poleConcrete: Material(color: 0xb3b1aa, variation: 0.08, hueVariation: 0.01)
        case .stripeYellow: Material(color: 0xe0b52a, variation: 0.06, hueVariation: 0.01)
        case .stripeBlack: Material(color: 0x202022, variation: 0.08)
        case .lampWarm: Material(color: 0xffd9a0, emission: 6, schedule: .night)
        case .lampCool: Material(color: 0xe8f2ff, emission: 5, schedule: .night)
        case .crossingLampA: Material(color: 0xff2a1a, emission: 8, schedule: .blinkA)
        case .crossingLampB: Material(color: 0xff2a1a, emission: 8, schedule: .blinkB)
        case .signalRed: Material(color: 0xff2a1a, emission: 8, schedule: .signalRed)
        case .signalYellow: Material(color: 0xffb21a, emission: 8, schedule: .signalYellow)
        case .signalGreen: Material(color: 0x1affb0, emission: 8, schedule: .signalGreen)
        case .vendingRed: Material(color: 0xc8202a, variation: 0.03)
        case .vendingBlue: Material(color: 0x2050b0, variation: 0.03)
        case .vendingPanel: Material(color: 0xf4f7ff, emission: 3)
        case .vendingButton: Material(color: 0xffe080, emission: 2)
        case .tile: Material(color: 0xd9d4c8, variation: 0.06, hueVariation: 0.01)
        case .tileWarm: Material(color: 0xcbb9a0, variation: 0.08, hueVariation: 0.02)
        case .plaster: Material(color: 0xe8e2d6, variation: 0.05, hueVariation: 0.01)
        case .frame: Material(color: 0x50555a, roughness: 0.5, variation: 0.03)
        case .wood: Material(color: 0x5a3c26, variation: 0.18, hueVariation: 0.05)
        case .woodLight: Material(color: 0x8a6440, variation: 0.16, hueVariation: 0.05)
        case .floorWood: Material(color: 0xa07850, variation: 0.14, hueVariation: 0.04)
        case .floorTile: Material(color: 0xe8e8e2, variation: 0.04)
        case .interiorWall: Material(color: 0xefe9dc, variation: 0.03)
        case .shelf: Material(color: 0xd8dde0, variation: 0.02)
        case .goodsRed: Material(color: 0xc84a3a, variation: 0.05, hueVariation: 0.01)
        case .goodsGreen: Material(color: 0x4aa060, variation: 0.05, hueVariation: 0.01)
        case .goodsYellow: Material(color: 0xe0c040, variation: 0.05, hueVariation: 0.01)
        case .goodsBlue: Material(color: 0x4a78c8, variation: 0.05, hueVariation: 0.01)
        case .roof: Material(color: 0x6c6e70, variation: 0.12, hueVariation: 0.02)
        case .acUnit: Material(color: 0xe0e0da, variation: 0.03)
        case .glass: Material(color: 0x9fc4d8, kind: .glass, roughness: 0.05)
        case .ceilingLight: Material(color: 0xf2f6ff, emission: 4)
        case .roomLight: Material(color: 0xffe2b8, emission: 4, schedule: .night)
        case .signWhite: Material(color: 0xf6f6f2, emission: 3)
        case .signGreen: Material(color: 0x18a058, emission: 3)
        case .signBlue: Material(color: 0x2a64d8, emission: 3)
        case .lantern: Material(color: 0xff3a24, emission: 5, schedule: .night)
        case .paperScreen: Material(color: 0xffe6b0, emission: 2.5, schedule: .night)
        case .neonPink: Material(color: 0xff3aa8, emission: 9)
        case .neonCyan: Material(color: 0x30e8ff, emission: 9)
        case .noren: Material(color: 0x283a6a, variation: 0.08, hueVariation: 0.03)
        case .roofRed: Material(color: 0x9c4032, variation: 0.14, hueVariation: 0.05)
        case .roofBlue: Material(color: 0x3f5a78, variation: 0.14, hueVariation: 0.04)
        case .roofBrown: Material(color: 0x5e4636, variation: 0.16, hueVariation: 0.05)
        case .brick: Material(color: 0x9a5a44, variation: 0.2, hueVariation: 0.07)
        case .siding: Material(color: 0xbfc4bd, variation: 0.05, hueVariation: 0.01)
        case .officeWall: Material(color: 0x848a92, variation: 0.06, hueVariation: 0.01)
        case .awningRed: Material(color: 0xb83a30, variation: 0.08, hueVariation: 0.02)
        case .awningGreen: Material(color: 0x2f7d4f, variation: 0.08, hueVariation: 0.02)
        case .awningBlue: Material(color: 0x2e5f9e, variation: 0.08, hueVariation: 0.02)
        case .awningCream: Material(color: 0xe8dfc8, variation: 0.08, hueVariation: 0.02)
        case .signOrange: Material(color: 0xf08a24, emission: 3)
        case .signRed: Material(color: 0xe0352b, emission: 3)
        case .trunk: Material(color: 0x5b4331, variation: 0.2, hueVariation: 0.05)
        case .leaves: Material(color: 0x3f7a35, variation: 0.28, hueVariation: 0.14)
        case .leavesLight: Material(color: 0x5a9440, variation: 0.28, hueVariation: 0.14)
        case .gravel: Material(color: 0xb5ad9e, variation: 0.3, hueVariation: 0.05)
        case .vermilion: Material(color: 0xc8412a, variation: 0.08, hueVariation: 0.02)
        case .carWhite: Material(color: 0xdfe2e4, roughness: 0.4)
        case .carRed: Material(color: 0xa82a2a, roughness: 0.4)
        case .carBlue: Material(color: 0x2d4f8c, roughness: 0.4)
        case .carBlack: Material(color: 0x222428, roughness: 0.4)
        case .skin: Material(color: 0xe8b894)
        case .hair: Material(color: 0x2a2220)
        case .shirt: Material(color: 0xd8dce6)
        case .jacket: Material(color: 0x2c3a5a)
        case .trousers: Material(color: 0x30323a)
        case .shoes: Material(color: 0x1c1c1e)
        case .bag: Material(color: 0x8a4a2a)
        }
    }

    private static let glassFlags: [Bool] = table.map { $0.kind == .glass }

    @inline(__always)
    static func isGlass(_ index: UInt8) -> Bool {
        glassFlags[Int(index)]
    }
}
