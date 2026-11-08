import RealModule
import VectorMath

/// An orthographic camera looking down on a point on the ground from one of
/// four diagonals, as in an isometric city builder.
struct IsometricCamera {
    /// The point on the ground at the center of the view, in meters, as
    /// doubles to stay precise far from the origin.
    var focusX: Double = 0
    var focusZ: Double = 0
    /// The angle around the vertical the camera looks from, in radians.
    var yaw: Float = .pi / 4
    /// Where `yaw` turns to, a quarter turn at a time.
    var targetYaw: Float = .pi / 4
    /// How far below the horizon the camera looks: 30°, as in 2:1 pixel art.
    var pitch: Float = .pi / 6
    /// Half the height of the view, in meters.
    var zoom: Float = 70

    static let zoomRange: ClosedRange<Float> = 12...260
    private static let eyeDistance: Float = 2000

    /// A whole number of meters near the focus, which positions on the GPU
    /// are relative to.
    var anchor: (x: Int, z: Int) {
        (Int(focusX.rounded(.down)), Int(focusZ.rounded(.down)))
    }

    /// The focus relative to the anchor.
    var focusOffset: Vector2<Float> {
        let anchor = anchor
        return Vector2(Float(focusX - Double(anchor.x)), Float(focusZ - Double(anchor.z)))
    }

    /// The direction from the focus to the eye.
    private var back: Vector3<Float> {
        Vector3(Float.cos(pitch) * Float.cos(yaw), Float.sin(pitch), Float.cos(pitch) * Float.sin(yaw))
    }

    /// The horizontal direction that is right on the screen.
    var screenRight: Vector2<Float> {
        Vector2(Float.sin(yaw), -Float.cos(yaw))
    }

    /// The horizontal direction that is up on the screen.
    var screenUp: Vector2<Float> {
        Vector2(-Float.cos(yaw), -Float.sin(yaw))
    }

    /// The transform from positions relative to the anchor to clip space.
    func viewProjection(aspectRatio: Float) -> Matrix4x4<Float> {
        let focus = focusOffset
        let target = Vector3<Float>(focus.x, 0, focus.y)
        let eye = target + back * Self.eyeDistance
        let projection = Matrix4x4<Float>.orthographic(
            left: -zoom * aspectRatio, right: zoom * aspectRatio, bottom: -zoom, top: zoom, near: 1,
            far: Self.eyeDistance * 2, handedness: .right, depth: .zeroToOne)
        let view = Matrix4x4<Float>.lookAt(eye: eye, target: target, up: Vector3(0, 1, 0), handedness: .right)
        return projection * view
    }

    /// Moves the focus so that the ground follows a drag of `delta` points
    /// on a canvas `canvasHeight` points tall.
    mutating func drag(by delta: Vector2<Float>, canvasHeight: Float) {
        let metersPerPoint = zoom * 2 / canvasHeight
        // Ground recedes up the screen, foreshortened by the pitch.
        let move = screenRight * (-delta.x * metersPerPoint) + screenUp * (delta.y * metersPerPoint / Float.sin(pitch))
        focusX += Double(move.x)
        focusZ += Double(move.y)
    }

    /// Moves the focus by `screen`, in the screen's directions, in meters.
    mutating func move(screen: Vector2<Float>) {
        let move = screenRight * screen.x + screenUp * screen.y
        focusX += Double(move.x)
        focusZ += Double(move.y)
    }

    mutating func zoom(by factor: Float) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    mutating func rotate(quarterTurns: Int) {
        targetYaw += Float(quarterTurns) * .pi / 2
    }

    /// Turns toward `targetYaw` for `duration` seconds.
    mutating func update(duration: Float) {
        let difference = targetYaw - yaw
        yaw = abs(difference) < 0.001 ? targetYaw : yaw + difference * min(duration * 12, 1)
    }
}
