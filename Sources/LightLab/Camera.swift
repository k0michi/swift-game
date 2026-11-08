import RealModule
import VectorMath

/// An orthographic camera looking down on a point, turning around the
/// vertical and tilting from low over the street to straight down.
struct Camera {
    /// The point at the center of the view, in meters.
    var focus: Vector3<Float>
    /// From the north-east, looking at the fronts of the buildings south of
    /// the road.
    var yaw: Float = -.pi / 4
    /// Where `yaw` turns to, as with a quarter turn.
    var targetYaw: Float = -.pi / 4
    var pitch: Float = .pi / 6 {
        didSet { pitch = min(max(pitch, Self.pitchRange.lowerBound), Self.pitchRange.upperBound) }
    }
    /// Half the height of the view, in meters.
    var zoom: Float = 12 {
        didSet { zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) }
    }

    static let pitchRange: ClosedRange<Float> = (.pi / 36)...(.pi / 2)
    static let zoomRange: ClosedRange<Float> = 2...40
    private static let eyeDistance: Float = 150

    /// The direction from the focus to the eye.
    private var back: Vector3<Float> {
        Vector3(Float.cos(pitch) * Float.cos(yaw), Float.sin(pitch), Float.cos(pitch) * Float.sin(yaw))
    }

    /// The direction the camera looks.
    var forward: Vector3<Float> { -back }

    /// The horizontal directions that are right and up on the screen.
    var screenRight: Vector2<Float> { Vector2(Float.sin(yaw), -Float.cos(yaw)) }
    var screenUp: Vector2<Float> { Vector2(-Float.cos(yaw), -Float.sin(yaw)) }

    func viewProjection(aspectRatio: Float) -> Matrix4x4<Float> {
        let eye = focus + back * Self.eyeDistance
        let up = Vector3<Float>(screenUp.x * Float.sin(pitch), Float.cos(pitch), screenUp.y * Float.sin(pitch))
        let projection = Matrix4x4<Float>.orthographic(
            left: -zoom * aspectRatio, right: zoom * aspectRatio, bottom: -zoom, top: zoom, near: 1,
            far: Self.eyeDistance * 2, handedness: .right, depth: .zeroToOne)
        let view = Matrix4x4<Float>.lookAt(eye: eye, target: focus, up: up, handedness: .right)
        return projection * view
    }

    /// Moves the focus so that the ground follows a drag of `delta` points on
    /// a canvas `canvasHeight` points tall.
    mutating func drag(by delta: Vector2<Float>, canvasHeight: Float) {
        let metersPerPoint = zoom * 2 / canvasHeight
        move(screen: Vector2(-delta.x * metersPerPoint, delta.y * metersPerPoint / Float.sin(pitch)))
    }

    /// Moves the focus by `screen`, in the screen's directions, in meters.
    mutating func move(screen: Vector2<Float>) {
        let move = screenRight * screen.x + screenUp * screen.y
        focus.x += move.x
        focus.z += move.y
    }

    mutating func orbit(yaw: Float, pitch: Float) {
        targetYaw += yaw
        self.yaw += yaw
        self.pitch += pitch
    }

    /// Turns to the next of the four diagonals, `quarterTurns` times.
    mutating func rotate(quarterTurns: Int) {
        let quarter = Float.pi / 2
        let diagonal = ((targetYaw - .pi / 4) / quarter).rounded() * quarter + .pi / 4
        targetYaw = diagonal + Float(quarterTurns) * quarter
    }

    mutating func update(duration: Float) {
        let difference = targetYaw - yaw
        yaw = abs(difference) < 0.001 ? targetYaw : yaw + difference * min(duration * 12, 1)
    }
}
