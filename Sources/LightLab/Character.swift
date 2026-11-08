import RealModule
import VectorMath

/// A person 1.75 m tall in 1/8 m voxels, in rigid parts that swing at
/// their joints: legs at the hips, arms at the shoulders. They walk free of
/// the grid, at any angle.
struct Character {
    /// A part's triangles, around its joint.
    private struct Part {
        var positions: [Vector3<Float>] = []
        var normals: [Vector3<Float>] = []
        /// Each vertex's material and occlusion, as packed in a VoxelMesh.
        var materials: [UInt32] = []
        var indices: [UInt32] = []
        /// Where the joint is, from the feet, in meters.
        var joint: Vector3<Float>

        /// The voxels of a box `size` voxels across, filled by `material`,
        /// with its lower corner at `origin` meters from the feet.
        init(
            size: (Int, Int, Int), origin: Vector3<Float>, joint: Vector3<Float>,
            material: (Int, Int, Int) -> UInt8
        ) {
            self.joint = joint
            var grid = VoxelGrid(width: size.0, height: size.1, depth: size.2)
            for y in 0..<size.1 {
                for z in 0..<size.2 {
                    for x in 0..<size.0 {
                        grid[x, y, z] = material(x, y, z)
                    }
                }
            }
            // Meshed apart from the ground, so that its underside shows.
            var lifted = VoxelGrid(width: size.0, height: size.1 + 1, depth: size.2)
            for y in 0..<size.1 {
                for z in 0..<size.2 {
                    for x in 0..<size.0 {
                        lifted[x, y + 1, z] = grid[x, y, z]
                    }
                }
            }
            let mesh = Mesher.mesh(lifted).opaque
            let scale = 1 / Float(voxelsPerMeter)
            for vertex in 0..<(mesh.vertices.count / VoxelMesh.wordsPerVertex) {
                let base = vertex * VoxelMesh.wordsPerVertex
                let position = Vector3(
                    Float(bitPattern: mesh.vertices[base]), Float(bitPattern: mesh.vertices[base + 1]) - scale,
                    Float(bitPattern: mesh.vertices[base + 2]))
                positions.append(position + origin)
                let packed = mesh.vertices[base + 3]
                func component(_ shift: UInt32) -> Float {
                    Float(Int8(bitPattern: UInt8((packed >> shift) & 0xff))) / 127
                }
                normals.append(Vector3(component(0), component(8), component(16)))
                materials.append(mesh.vertices[base + 4])
            }
            indices = mesh.indices
        }
    }

    private var parts: [Part] = []
    /// Where the feet are, in meters.
    var position: Vector3<Float>
    /// The angle around the vertical the person faces, from +z toward +x.
    var heading: Float = .pi / 2
    /// How far the stride has gone, in radians.
    private var stride: Float = 0
    private var direction: Float = 1

    /// The ends of the walk along x.
    let walk: ClosedRange<Float>
    let speed: Float = 1.3

    init(at position: Vector3<Float>, walking walk: ClosedRange<Float>) {
        self.position = position
        self.walk = walk
        let s = 1 / Float(voxelsPerMeter)
        // Legs: trousers over shoes, 6 voxels tall.
        for side: Float in [-1, 1] {
            let x0 = side < 0 ? -2 * s : 0
            parts.append(
                Part(size: (2, 6, 2), origin: Vector3(x0, 0, -s), joint: Vector3(0, 6 * s, 0)) { _, y, _ in
                    y == 0 ? Materials.shoes : Materials.trousers
                })
        }
        // The torso: a jacket open over a shirt.
        parts.append(
            Part(size: (4, 5, 2), origin: Vector3(-2 * s, 6 * s, -s), joint: .zero) { x, y, z in
                z == 1 && (x == 1 || x == 2) && y >= 2 ? Materials.shirt : Materials.jacket
            })
        // The head: hair on top and at the back, and two eyes.
        parts.append(
            Part(size: (3, 3, 3), origin: Vector3(-1.5 * s, 11 * s, -1.5 * s), joint: .zero) { x, y, z in
                if y == 2 || z == 0 { return Materials.hair }
                if y == 1 && z == 2 && x != 1 { return Materials.hair }
                return Materials.skin
            })
        // Arms: sleeves and hands, swinging at the shoulders.
        for side: Float in [-1, 1] {
            let x0 = side < 0 ? -3 * s : 2 * s
            parts.append(
                Part(size: (1, 5, 1), origin: Vector3(x0, 6 * s, -0.5 * s), joint: Vector3(0, 10.5 * s, 0)) {
                    _, y, _ in
                    y == 0 ? Materials.skin : Materials.jacket
                })
        }
    }

    /// Walks for `duration` seconds, turning back at the ends.
    mutating func update(duration: Float) {
        position.x += direction * speed * duration
        if position.x > walk.upperBound {
            position.x = walk.upperBound
            direction = -1
        } else if position.x < walk.lowerBound {
            position.x = walk.lowerBound
            direction = 1
        }
        let target: Float = direction > 0 ? .pi / 2 : -.pi / 2
        heading += (target - heading) * min(duration * 8, 1)
        stride += speed * duration / 0.75 * .pi
    }

    /// The triangles in the world, as they stand now.
    func mesh() -> VoxelMesh {
        var mesh = VoxelMesh()
        let swing = Float.sin(stride)
        let bob = abs(Float.cos(stride)) * 0.03
        let body = Matrix4x4<Float>.translation(position + Vector3(0, bob, 0))
            * .rotation(angle: heading, axis: Vector3(0, 1, 0))
        // Legs, then the torso and head, then the arms, swinging opposite.
        let angles: [Float] = [swing * 0.5, -swing * 0.5, 0, 0, -swing * 0.4, swing * 0.4]
        for (part, angle) in zip(parts, angles) {
            let joint = Matrix4x4<Float>.translation(part.joint)
                * .rotation(angle: angle, axis: Vector3(1, 0, 0))
                * .translation(-part.joint)
            let transform = body * joint
            let first = UInt32(mesh.vertices.count / VoxelMesh.wordsPerVertex)
            for index in part.positions.indices {
                let p = transform * Vector4(part.positions[index], 1)
                let n = transform * Vector4(part.normals[index], 0)
                mesh.vertices += [
                    p.x.bitPattern, p.y.bitPattern, p.z.bitPattern, VoxelMesh.packNormal(n.xyz),
                    part.materials[index],
                ]
            }
            mesh.indices += part.indices.map { $0 + first }
        }
        return mesh
    }
}
