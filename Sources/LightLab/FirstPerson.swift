import RealModule
import VectorMath

/// A view from the eyes of someone walking through the voxels: stopped by
/// what is solid, climbing low steps, jumping and falling off ledges.
struct FirstPerson {
    /// Where the feet are, in meters.
    private(set) var feet: Vector3<Float>
    /// The angle the view is turned, clockwise from above, from looking north
    /// along -z.
    var yaw: Float
    /// How far above the horizon the view looks.
    var pitch: Float = 0 {
        didSet { pitch = min(max(pitch, -Self.pitchLimit), Self.pitchLimit) }
    }
    /// How fast the body is falling, or rising if negative.
    private var fallSpeed: Float = 0
    private var isOnGround = false
    /// The height of the eyes, which eases over steps.
    private var eyeY: Float

    static let eyeHeight: Float = 1.6
    private static let height: Float = 1.7
    private static let radius: Float = 0.2
    /// The highest step walked up without jumping: three voxels.
    private static let stepHeight = 3
    private static let walkSpeed: Float = 2.2
    private static let runSpeed: Float = 5
    private static let gravity: Float = 12
    private static let jumpHeight: Float = 1
    private static let pitchLimit: Float = 1.5
    private static let fieldOfView: Float = 70 * .pi / 180
    private static let lookPerPoint: Float = 0.0025

    private static var voxel: Float { 1 / Float(voxelsPerMeter) }

    init(feet: Vector3<Float>, yaw: Float) {
        self.feet = feet
        self.yaw = yaw
        eyeY = feet.y + Self.eyeHeight
    }

    var eye: Vector3<Float> { Vector3(feet.x, eyeY, feet.z) }

    var forward: Vector3<Float> {
        Vector3(Float.cos(pitch) * Float.sin(yaw), Float.sin(pitch), -Float.cos(pitch) * Float.cos(yaw))
    }

    func viewProjection(aspectRatio: Float) -> Matrix4x4<Float> {
        let projection = Matrix4x4<Float>.perspective(
            fovY: Self.fieldOfView, aspectRatio: aspectRatio, near: 0.05, far: 150, handedness: .right,
            depth: .zeroToOne)
        let view = Matrix4x4<Float>.lookAt(eye: eye, target: eye + forward, up: Vector3(0, 1, 0), handedness: .right)
        return projection * view
    }

    /// Turns the view as the mouse moved by `delta` points.
    mutating func look(by delta: Vector2<Float>) {
        yaw += delta.x * Self.lookPerPoint
        pitch -= delta.y * Self.lookPerPoint
    }

    /// Leaps, if standing on something.
    mutating func jump() {
        guard isOnGround else { return }
        isOnGround = false
        fallSpeed = -(2 * Self.gravity * Self.jumpHeight).squareRoot()
    }

    /// Walks for `duration` seconds, by `input`: x to the right of the view,
    /// y ahead.
    mutating func update(input: Vector2<Float>, running: Bool, duration: Float, grid: SparseVoxels) {
        // Placed inside something, as on a raised sidewalk, rises out of it.
        while collides(x: feet.x, y: feet.y, z: feet.z, grid: grid) {
            feet.y += Self.voxel
        }
        if input.x != 0 || input.y != 0 {
            let right = Vector2<Float>(Float.cos(yaw), Float.sin(yaw))
            let ahead = Vector2<Float>(Float.sin(yaw), -Float.cos(yaw))
            let direction = normalize(right * input.x + ahead * input.y)
            let distance = (running ? Self.runSpeed : Self.walkSpeed) * duration
            // In steps shorter than a voxel, so that nothing is passed through.
            let steps = max(Int((distance / (Self.voxel / 2)).rounded(.up)), 1)
            let step = direction * (distance / Float(steps))
            for _ in 0..<steps {
                walk(dx: step.x, dz: 0, grid: grid)
                walk(dx: 0, dz: step.y, grid: grid)
            }
        }

        // The mean speed over the frame, so that a leap is as high at any
        // frame rate.
        let speedBefore = fallSpeed
        fallSpeed += Self.gravity * duration
        let moved = (speedBefore + fallSpeed) / 2 * duration
        var rise = -moved
        while rise > 0 {
            let lift = min(rise, Self.voxel / 2)
            if collides(x: feet.x, y: feet.y + lift, z: feet.z, grid: grid) {
                // A ceiling ends the leap.
                fallSpeed = 0
                break
            }
            feet.y += lift
            rise -= lift
        }

        isOnGround = false
        var fall = moved
        while fall > 0 {
            let drop = min(fall, Self.voxel / 2)
            if collides(x: feet.x, y: feet.y - drop, z: feet.z, grid: grid) {
                // Stands on the top of the voxel below.
                feet.y = (feet.y * Float(voxelsPerMeter)).rounded(.down) * Self.voxel
                fallSpeed = 0
                isOnGround = true
                break
            }
            feet.y -= drop
            fall -= drop
        }

        let target = feet.y + Self.eyeHeight
        eyeY += (target - eyeY) * min(duration * 14, 1)
    }

    /// Moves along the ground if the way is clear, or up a low step.
    private mutating func walk(dx: Float, dz: Float, grid: SparseVoxels) {
        let margin = Self.radius + 0.01
        let x = min(max(feet.x + dx, margin), Float(grid.width) * Self.voxel - margin)
        let z = min(max(feet.z + dz, margin), Float(grid.depth) * Self.voxel - margin)
        for rise in 0...Self.stepHeight {
            let y = feet.y + Float(rise) * Self.voxel
            if !collides(x: x, y: y, z: z, grid: grid) {
                feet = Vector3(x, y, z)
                return
            }
        }
    }

    /// Whether a body with its feet at a point would be inside anything,
    /// glass included.
    private func collides(x: Float, y: Float, z: Float, grid: SparseVoxels) -> Bool {
        let scale = Float(voxelsPerMeter)
        let xs = Int(((x - Self.radius) * scale).rounded(.down))...Int(((x + Self.radius) * scale).rounded(.down))
        let zs = Int(((z - Self.radius) * scale).rounded(.down))...Int(((z + Self.radius) * scale).rounded(.down))
        let ys = Int((y * scale).rounded(.down))...Int(((y + Self.height) * scale).rounded(.down))
        for cellY in ys {
            for cellZ in zs {
                for cellX in xs where grid[cellX, cellY, cellZ] != Materials.air {
                    return true
                }
            }
        }
        return false
    }
}
