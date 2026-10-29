// The WGSL built-in functions on scalars that Swift does not already have. The
// generated sources apply them to each component of a vector.

/// `t` if `condition` is true, and `f` otherwise.
@inlinable
public func select<T>(_ f: T, _ t: T, _ condition: Bool) -> T {
    condition ? t : f
}

/// `e`, limited to the range from `low` to `high`.
@inlinable
public func clamp<T: Comparable>(_ e: T, _ low: T, _ high: T) -> T {
    Swift.min(Swift.max(e, low), high)
}

/// The sign of `e`: -1, 0 or 1.
@inlinable
public func sign<T: SignedNumeric & Comparable>(_ e: T) -> T {
    e > 0 ? 1 : e < 0 ? -1 : 0
}

/// The fractional part of `e`, `e - floor(e)`.
@inlinable
public func fract<T: FloatingPoint>(_ e: T) -> T {
    e - e.rounded(.down)
}

/// The reciprocal of the square root of `e`.
@inlinable
public func inverseSqrt<T: FloatingPoint>(_ e: T) -> T {
    1 / e.squareRoot()
}

/// `e`, limited to the range from 0 to 1.
@inlinable
public func saturate<T: FloatingPoint>(_ e: T) -> T {
    clamp(e, 0, 1)
}

/// `e` converted from radians to degrees.
@inlinable
public func degrees<T: FloatingPoint>(_ e: T) -> T {
    e * 180 / .pi
}

/// `e` converted from degrees to radians.
@inlinable
public func radians<T: FloatingPoint>(_ e: T) -> T {
    e * .pi / 180
}

/// 1 if `x` is at or above `edge`, and 0 otherwise.
@inlinable
public func step<T: FloatingPoint>(_ edge: T, _ x: T) -> T {
    x >= edge ? 1 : 0
}

/// `x` mapped smoothly from the range from `low` to `high` onto 0 to 1.
@inlinable
public func smoothstep<T: FloatingPoint>(_ low: T, _ high: T, _ x: T) -> T {
    let t = saturate((x - low) / (high - low))
    return t * t * (3 - 2 * t)
}

/// The linear blend of `e1` and `e2` by `e3`: `e1` at 0 and `e2` at 1.
@inlinable
public func mix<T: FloatingPoint>(_ e1: T, _ e2: T, _ e3: T) -> T {
    e1 * (1 - e3) + e2 * e3
}
