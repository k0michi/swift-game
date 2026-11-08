import Testing
import VectorMath

@testable import LightLab

@Suite("Town")
struct TownTests {
    private static let seed: UInt64 = 20_261_108

    private func voxels(of town: Town) -> [UInt8] {
        town.grid.data
    }

    /// The lamps of a town as sortable positions.
    private func lamps(of town: Town) -> [[Float]] {
        town.lights.map { [$0.position.x, $0.position.y, $0.position.z, $0.radius] }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    @Test
    func aRegionComesOutTheSameEveryTime() {
        let first = Town(seed: Self.seed, x: 0..<256, z: 0..<256)
        let second = Town(seed: Self.seed, x: 0..<256, z: 0..<256)
        #expect(voxels(of: first) == voxels(of: second))
        #expect(lamps(of: first) == lamps(of: second))
    }

    @Test
    func anotherSeedMakesAnotherTown() {
        let first = Town(seed: Self.seed, x: 0..<512, z: 0..<512)
        let second = Town(seed: Self.seed + 1, x: 0..<512, z: 0..<512)
        #expect(voxels(of: first) != voxels(of: second))
    }

    /// Cut anywhere, a region must equal the same region made whole.
    @Test(arguments: [(600, 700), (0, 0), (-512, 1400), (2048, -256), (800, 780)])
    func piecesAgreeWithTheWhole(x: Int, z: Int) {
        let whole = Town(seed: Self.seed, x: x..<(x + 256), z: z..<(z + 128))
        let left = Town(seed: Self.seed, x: x..<(x + 128), z: z..<(z + 128))
        let right = Town(seed: Self.seed, x: (x + 128)..<(x + 256), z: z..<(z + 128))
        var joined = [UInt8]()
        joined.reserveCapacity(whole.grid.data.count)
        for row in 0..<(left.grid.height * left.grid.depth) {
            joined += left.grid.data[(row * 128)..<((row + 1) * 128)]
            joined += right.grid.data[(row * 128)..<((row + 1) * 128)]
        }
        #expect(joined == whole.grid.data)
        let lampsOfPieces = (lamps(of: left) + lamps(of: right)).sorted { $0.lexicographicallyPrecedes($1) }
        #expect(lampsOfPieces == lamps(of: whole))
    }

    @Test
    func theRailsRunAcrossAnyRegion() {
        // Row of the rail at the town's level, past any crossing.
        for start in [0, 1600, -3200, 16000] {
            let town = Town(seed: Self.seed, x: start..<(start + 128), z: 0..<1000)
            let railLayer = cells(Scene.streetLevel + 0.5)
            let rows = (0..<town.grid.depth).filter { z in
                (0..<town.grid.width).allSatisfy { x in town.grid[x, railLayer, z] == Materials.rail }
            }
            #expect(!rows.isEmpty)
        }
    }

    @Test
    func theSpawnIsOnARoad() {
        let spawn = Town.spawn(seed: Self.seed, near: Vector2(100, 100))
        let (x, z) = (cells(spawn.x), cells(spawn.y))
        let town = Town(seed: Self.seed, x: x..<(x + 8), z: z..<(z + 8))
        #expect(town.grid[0, cells(Scene.streetLevel) - 1, 0] == Materials.asphalt)
    }
}
