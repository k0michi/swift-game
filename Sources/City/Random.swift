/// Hashes of integer coordinates, so that any part of the endless city comes
/// out the same however often, and in whatever order, it is generated.
enum Hash {
    /// SplitMix64's finalizer.
    @inline(__always)
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    @inline(__always)
    static func of(_ a: Int, _ b: Int = 0, _ c: Int = 0, salt: UInt64) -> UInt64 {
        var h = mix(salt)
        h = mix(h ^ UInt64(bitPattern: Int64(a)))
        h = mix(h ^ UInt64(bitPattern: Int64(b)))
        h = mix(h ^ UInt64(bitPattern: Int64(c)))
        return h
    }

    /// A number from 0 up to 1, from a hash.
    @inline(__always)
    static func unit(_ hash: UInt64) -> Float {
        Float(hash >> 40) / Float(1 << 24)
    }
}

/// A small random number generator for laying out one block or building,
/// seeded by a hash of where it is.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 1
        return Hash.mix(state)
    }

    /// A number from 0 up to 1.
    mutating func unit() -> Float {
        Hash.unit(next())
    }

    /// An integer in `range`.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Float) -> Bool {
        unit() < probability
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[Int(next() % UInt64(values.count))]
    }
}

/// Smooth value noise over the plane, from 0 to 1, with features about
/// `scale` meters across.
func valueNoise(x: Float, z: Float, scale: Float, salt: UInt64) -> Float {
    let fx = x / scale
    let fz = z / scale
    let ix = Int(fx.rounded(.down))
    let iz = Int(fz.rounded(.down))
    let tx = fx - Float(ix)
    let tz = fz - Float(iz)
    let sx = tx * tx * (3 - 2 * tx)
    let sz = tz * tz * (3 - 2 * tz)
    let a = Hash.unit(Hash.of(ix, iz, salt: salt))
    let b = Hash.unit(Hash.of(ix + 1, iz, salt: salt))
    let c = Hash.unit(Hash.of(ix, iz + 1, salt: salt))
    let d = Hash.unit(Hash.of(ix + 1, iz + 1, salt: salt))
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sz
}

/// The floor of `a / b`, for a positive `b`.
@inline(__always)
func floorDivide(_ a: Int, _ b: Int) -> Int {
    a >= 0 ? a / b : -((-a + b - 1) / b)
}

/// `a` modulo `b`, from 0 up to `b`, for a positive `b`.
@inline(__always)
func floorModulo(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
}
