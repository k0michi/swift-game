import RealModule

// Transform and projection matrices, for column vectors: a transform applies
// to `matrix * vector`, and `a * b` applies `b` first. Angles are in radians.
//
// Conventions differ between APIs, so the projections take them as arguments
// rather than assuming one: which way the eye looks, and which range of clip
// space depths the near and far planes map to.

/// Which way the eye looks along the z axis of view space.
public enum Handedness: Sendable {
    /// The eye looks toward -z, with x right and y up, as in OpenGL.
    case right
    /// The eye looks toward +z, with x right and y up, as in Direct3D.
    case left
}

/// The clip space depths that the near and the far plane map to.
public enum ClipDepth: Sendable {
    /// Near at 0 and far at 1, as in WebGPU, Metal, Vulkan and Direct3D.
    case zeroToOne
    /// Near at 1 and far at 0: reversed Z, which spreads depth precision more
    /// evenly with floating-point depth buffers.
    case oneToZero
    /// Near at -1 and far at 1, as in OpenGL.
    case negativeOneToOne

    @usableFromInline
    func range<Scalar: FloatingPoint>(of _: Scalar.Type) -> (near: Scalar, far: Scalar) {
        switch self {
        case .zeroToOne: (0, 1)
        case .oneToZero: (1, 0)
        case .negativeOneToOne: (-1, 1)
        }
    }
}

extension Handedness {
    /// The sign of view space z in front of the eye.
    @usableFromInline
    func forward<Scalar: FloatingPoint>(_: Scalar.Type) -> Scalar {
        switch self {
        case .right: -1
        case .left: 1
        }
    }
}

extension Matrix4x4 where Scalar: Numeric {
    /// The transform that moves points by `offset`.
    @inlinable
    public static func translation(_ offset: Vector3<Scalar>) -> Self {
        Self(
            Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0),
            Vector4(offset, 1))
    }

    /// The transform that scales points by `factors` along each axis.
    @inlinable
    public static func scale(_ factors: Vector3<Scalar>) -> Self {
        Self(
            Vector4(factors.x, 0, 0, 0), Vector4(0, factors.y, 0, 0), Vector4(0, 0, factors.z, 0),
            Vector4(0, 0, 0, 1))
    }
}

extension Matrix4x4 where Scalar: Real {
    /// The rotation by `angle` around `axis`, counterclockwise when the axis
    /// points toward the viewer. The axis need not have a length of 1.
    @inlinable
    public static func rotation(angle: Scalar, axis: Vector3<Scalar>) -> Self {
        let unit = normalize(axis)
        let (x, y, z) = (unit.x, unit.y, unit.z)
        let c = cos(angle)
        let s = sin(angle)
        let t: Scalar = 1 - c
        return Self(
            Vector4(t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0),
            Vector4(t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0),
            Vector4(t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0),
            Vector4(0, 0, 0, 1))
    }

    /// The perspective projection with the vertical field of view `fovY`, for a
    /// viewport `aspectRatio` times as wide as it is high. `far` can be
    /// infinite.
    @inlinable
    public static func perspective(
        fovY: Scalar, aspectRatio: Scalar, near: Scalar, far: Scalar,
        handedness: Handedness, depth: ClipDepth
    ) -> Self {
        let top: Scalar = near * tan(fovY / 2)
        let right: Scalar = top * aspectRatio
        return frustum(
            left: -right, right: right, bottom: -top, top: top, near: near, far: far,
            handedness: handedness, depth: depth)
    }
}

extension Matrix4x4 where Scalar: FloatingPoint {
    /// The orthographic projection of the box from `left` to `right`, `bottom`
    /// to `top` and, along the direction the eye looks, `near` to `far`.
    ///
    /// For y down, as for window coordinates, pass the bottom edge as `bottom`
    /// and the top edge as `top`, so that `bottom` is the larger.
    @inlinable
    public static func orthographic(
        left: Scalar, right: Scalar, bottom: Scalar, top: Scalar, near: Scalar, far: Scalar,
        handedness: Handedness, depth: ClipDepth
    ) -> Self {
        let range = depth.range(of: Scalar.self)
        let forward = handedness.forward(Scalar.self)
        // Depth is linear in the distance in front of the eye, forward * z.
        let depthScale: Scalar = (range.far - range.near) / (far - near)
        let depthOffset: Scalar = range.near - depthScale * near
        let width: Scalar = right - left
        let height: Scalar = top - bottom
        return Self(
            Vector4(2 / width, 0, 0, 0),
            Vector4(0, 2 / height, 0, 0),
            Vector4(0, 0, depthScale * forward, 0),
            Vector4(-(right + left) / width, -(top + bottom) / height, depthOffset, 1))
    }

    /// The perspective projection of the frustum whose near plane spans from
    /// `left` to `right` and `bottom` to `top`, at the distance `near` in front
    /// of the eye. `far` can be infinite.
    @inlinable
    public static func frustum(
        left: Scalar, right: Scalar, bottom: Scalar, top: Scalar, near: Scalar, far: Scalar,
        handedness: Handedness, depth: ClipDepth
    ) -> Self {
        let range = depth.range(of: Scalar.self)
        let forward = handedness.forward(Scalar.self)
        // w is the distance in front of the eye, d = forward * z, and depth is
        // a + b / d, which is range.near at near and range.far at far.
        let a: Scalar
        let b: Scalar
        if far.isInfinite {
            a = range.far
            b = (range.near - range.far) * near
        } else {
            a = (range.far * far - range.near * near) / (far - near)
            b = (range.near - range.far) * near * far / (far - near)
        }
        let width: Scalar = right - left
        let height: Scalar = top - bottom
        return Self(
            Vector4(2 * near / width, 0, 0, 0),
            Vector4(0, 2 * near / height, 0, 0),
            Vector4(-(right + left) / width * forward, -(top + bottom) / height * forward, a * forward, forward),
            Vector4(0, 0, b, 0))
    }

    /// The view transform of an eye at `eye` looking at `target`, with `up`
    /// pointing roughly up.
    @inlinable
    public static func lookAt(
        eye: Vector3<Scalar>, target: Vector3<Scalar>, up: Vector3<Scalar>, handedness: Handedness
    ) -> Self {
        // The eye's axes in world space: x right, y up and z backward or
        // forward, as the handedness says.
        let forward = normalize(target - eye)
        let zAxis = forward * handedness.forward(Scalar.self)
        let xAxis = normalize(cross(up, zAxis))
        let yAxis = cross(zAxis, xAxis)
        return Self(
            rows: (
                Vector4(xAxis, -dot(xAxis, eye)),
                Vector4(yAxis, -dot(yAxis, eye)),
                Vector4(zAxis, -dot(zAxis, eye)),
                Vector4(0, 0, 0, 1)
            ))
    }
}

// 2D transforms of points in homogeneous coordinates, (x, y, 1).

extension Matrix3x3 where Scalar: Numeric {
    /// The 2D transform that moves points by `offset`.
    @inlinable
    public static func translation(_ offset: Vector2<Scalar>) -> Self {
        Self(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(offset, 1))
    }

    /// The 2D transform that scales points by `factors` along each axis.
    @inlinable
    public static func scale(_ factors: Vector2<Scalar>) -> Self {
        Self(Vector3(factors.x, 0, 0), Vector3(0, factors.y, 0), Vector3(0, 0, 1))
    }
}

extension Matrix3x3 where Scalar: Real {
    /// The 2D rotation by `angle`, from the x axis toward the y axis.
    @inlinable
    public static func rotation(angle: Scalar) -> Self {
        let c = cos(angle)
        let s = sin(angle)
        return Self(Vector3(c, s, 0), Vector3(-s, c, 0), Vector3(0, 0, 1))
    }
}
