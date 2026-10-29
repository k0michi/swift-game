import RealModule

// WGSL's transcendental built-in functions on scalars, for any `Real` from
// swift-numerics, which Float, Double and Float16 are. The generated sources
// apply them to each component of a vector.
//
// As with Functions.swift, files that import Foundation call these with the
// module name, as in `VectorMath.sin(x)`.

/// The sine of `e`, in radians.
@inlinable
public func sin<T: Real>(_ e: T) -> T {
    T.sin(e)
}

/// The cosine of `e`, in radians.
@inlinable
public func cos<T: Real>(_ e: T) -> T {
    T.cos(e)
}

/// The tangent of `e`, in radians.
@inlinable
public func tan<T: Real>(_ e: T) -> T {
    T.tan(e)
}

/// The arcsine of `e`, in radians.
@inlinable
public func asin<T: Real>(_ e: T) -> T {
    T.asin(e)
}

/// The arccosine of `e`, in radians.
@inlinable
public func acos<T: Real>(_ e: T) -> T {
    T.acos(e)
}

/// The arctangent of `e`, in radians.
@inlinable
public func atan<T: Real>(_ e: T) -> T {
    T.atan(e)
}

/// The angle of the point (`x`, `y`) from the positive x axis, in radians.
@inlinable
public func atan2<T: Real>(_ y: T, _ x: T) -> T {
    T.atan2(y: y, x: x)
}

/// The hyperbolic sine of `e`.
@inlinable
public func sinh<T: Real>(_ e: T) -> T {
    T.sinh(e)
}

/// The hyperbolic cosine of `e`.
@inlinable
public func cosh<T: Real>(_ e: T) -> T {
    T.cosh(e)
}

/// The hyperbolic tangent of `e`.
@inlinable
public func tanh<T: Real>(_ e: T) -> T {
    T.tanh(e)
}

/// The inverse hyperbolic sine of `e`.
@inlinable
public func asinh<T: Real>(_ e: T) -> T {
    T.asinh(e)
}

/// The inverse hyperbolic cosine of `e`.
@inlinable
public func acosh<T: Real>(_ e: T) -> T {
    T.acosh(e)
}

/// The inverse hyperbolic tangent of `e`.
@inlinable
public func atanh<T: Real>(_ e: T) -> T {
    T.atanh(e)
}

/// Euler's number raised to `e`.
@inlinable
public func exp<T: Real>(_ e: T) -> T {
    T.exp(e)
}

/// 2 raised to `e`.
@inlinable
public func exp2<T: Real>(_ e: T) -> T {
    T.exp2(e)
}

/// The natural logarithm of `e`.
@inlinable
public func log<T: Real>(_ e: T) -> T {
    T.log(e)
}

/// The base-2 logarithm of `e`.
@inlinable
public func log2<T: Real>(_ e: T) -> T {
    T.log2(e)
}

/// `e1` raised to `e2`.
@inlinable
public func pow<T: Real>(_ e1: T, _ e2: T) -> T {
    T.pow(e1, e2)
}
