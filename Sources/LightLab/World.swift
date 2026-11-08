/// The voxels and lamps known so far, which a generated town fills in as
/// chunks are made.
final class World {
    /// The most lamps the shaders are given room for.
    static let maxLamps = 4096

    private(set) var voxels: SparseVoxels
    var lights: [PointLight] = []
    /// What the chunks are generated from, if anything: without it, all the
    /// voxels are already there.
    let seed: UInt64?
    /// How many chunks the world is each way, counting those it fills only
    /// in part.
    let chunksX: Int
    let chunksZ: Int
    private var generated: [Bool]

    init(voxels: SparseVoxels, seed: UInt64? = nil) {
        self.voxels = voxels
        self.seed = seed
        let size = SceneChunk.size
        chunksX = (voxels.width + size - 1) / size
        chunksZ = (voxels.depth + size - 1) / size
        generated = [Bool](repeating: seed == nil, count: chunksX * chunksZ)
    }

    /// The place of a chunk in arrays of all of them, if it is in the world.
    func index(of chunk: SIMD2<Int>) -> Int? {
        guard chunk.x >= 0, chunk.x < chunksX, chunk.y >= 0, chunk.y < chunksZ else { return nil }
        return chunk.y * chunksX + chunk.x
    }

    /// Whether a chunk's voxels are final; past the world's edges, they are
    /// air for good.
    func isSettled(_ chunk: SIMD2<Int>) -> Bool {
        index(of: chunk).map { generated[$0] } ?? true
    }

    /// The start of generating a chunk, with its lots left to build.
    func startGenerating(_ chunk: SIMD2<Int>) -> Town {
        let size = SceneChunk.size
        return Town(
            seed: seed ?? 0, x: (chunk.x * size)..<((chunk.x + 1) * size), z: (chunk.y * size)..<((chunk.y + 1) * size),
            lotsLater: true)
    }

    /// Takes in a generated chunk, and says whether it brought lamps.
    func finishGenerating(_ chunk: SIMD2<Int>, town: Town) -> Bool {
        guard let index = index(of: chunk) else { return false }
        let size = SceneChunk.size
        voxels.set(town.grid, originX: chunk.x * size, originZ: chunk.y * size)
        generated[index] = true
        let (width, depth) = (Float(voxels.width), Float(voxels.depth))
        let scale = Float(voxelsPerMeter)
        let found = town.lights.filter { $0.position.x * scale < width && $0.position.z * scale < depth }
        lights += found.prefix(max(Self.maxLamps - lights.count, 0))
        return !found.isEmpty
    }
}
