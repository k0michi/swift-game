// The WGSL built-in functions on scalars that Swift does not already have, and
// those whose Swift counterparts behave differently. The generated sources apply
// them to each component of a vector.
//
// Where Foundation is imported too, its functions of the same name take
// precedence for concrete types such as Double, so these are called with the
// module name, as in `VectorMath.round(x)`.

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

/// `e` rounded down to an integer.
@inlinable
public func floor<T: FloatingPoint>(_ e: T) -> T {
    e.rounded(.down)
}

/// `e` rounded up to an integer.
@inlinable
public func ceil<T: FloatingPoint>(_ e: T) -> T {
    e.rounded(.up)
}

/// `e` rounded toward zero to an integer.
@inlinable
public func trunc<T: FloatingPoint>(_ e: T) -> T {
    e.rounded(.towardZero)
}

/// The square root of `e`.
@inlinable
public func sqrt<T: FloatingPoint>(_ e: T) -> T {
    e.squareRoot()
}

/// `e` rounded to the nearest integer, with halfway values rounded to the even
/// one, as in WGSL: `round(2.5)` is 2. The C `round` that Foundation has rounds
/// them away from zero instead.
@inlinable
public func round<T: FloatingPoint>(_ e: T) -> T {
    e.rounded(.toNearestOrEven)
}

/// The fractional part of `e`, `e - floor(e)`.
@inlinable
public func fract<T: FloatingPoint>(_ e: T) -> T {
    e - floor(e)
}

/// The reciprocal of the square root of `e`.
@inlinable
public func inverseSqrt<T: FloatingPoint>(_ e: T) -> T {
    1 / sqrt(e)
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
