/// The colors a voxel can be: each voxel is one solid color, stored as its
/// index here. Index 0 is air.
enum Palette {
    // Each color is 0xRRGGBB.
    static let colors: [UInt32] = [
        0x000000,  // air
        // Ground.
        0x3a3d42,  // asphalt
        0xa9a59c,  // sidewalk
        0xe8e4d8,  // road marking
        0xd9b23a,  // center line
        0x5f9a3e,  // grass
        0x4f8434,  // grass, darker
        0x8a8579,  // plaza paving
        // Trees.
        0x6b4a2f,  // trunk
        0x3f7d32,  // leaves
        0x2f6a2a,  // leaves, darker
        0x5c8f2c,  // leaves, lighter
        // Walls.
        0xe9e1cf,  // cream
        0xf3f1ea,  // white
        0xd7c3a1,  // beige
        0xb9c7cf,  // pale blue
        0xc96f4a,  // brick
        0x9c5a3c,  // dark brick
        0x8e9196,  // concrete
        0x6e7277,  // dark concrete
        0xb7b2a8,  // stone
        0xd8d1c0,  // limestone
        // Glass.
        0x2c4a63,  // blue glass
        0x3d5e5a,  // green glass
        0x24323f,  // dark glass
        0x6f8fa6,  // light glass
        0x8fb3c9,  // pale glass
        // Roofs.
        0xa3402f,  // red tile
        0x5b5f66,  // slate
        0x7a5236,  // brown tile
        0x9aa0a3,  // roof gravel
        0x4f5559,  // roof dark
        0xcfd3d1,  // roof equipment
    ]

    static let air: UInt8 = 0
    static let asphalt: UInt8 = 1
    static let sidewalk: UInt8 = 2
    static let marking: UInt8 = 3
    static let centerLine: UInt8 = 4
    static let grass: UInt8 = 5
    static let darkGrass: UInt8 = 6
    static let plaza: UInt8 = 7
    static let trunk: UInt8 = 8
    static let leaves: [UInt8] = [9, 10, 11]
    static let houseWalls: [UInt8] = [12, 13, 14, 15, 16]
    static let apartmentWalls: [UInt8] = [12, 14, 16, 17, 20, 21]
    static let officeWalls: [UInt8] = [13, 18, 19, 20, 21]
    static let glass: [UInt8] = [22, 23, 24, 25, 26]
    static let houseRoofs: [UInt8] = [27, 28, 29]
    static let flatRoofs: [UInt8] = [30, 31]
    static let equipment: UInt8 = 32

    /// The color of `index` as 0xAABBGGRR, the bytes of an RGBA unorm8x4
    /// vertex attribute in little-endian memory.
    static let rgba: [UInt32] = colors.map { color in
        let r = (color >> 16) & 0xff
        let g = (color >> 8) & 0xff
        let b = color & 0xff
        return r | g << 8 | b << 16
    }
}
