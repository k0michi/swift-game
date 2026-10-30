import VectorMath

// The world is in units, with y up and the enemies coming from far down -z
// toward the ship, which flies in the plane z = 0.

/// How far the ship can move from the middle of the plane.
let shipBounds = Vector2<Float>(6, 3.5)
/// Half the ship's size along each axis, roughly the box of its pyramid,
/// which hits use as its shape.
let shipHalfExtent = Vector3<Float>(0.5, 0.2, 0.9)
/// How fast the ship flies toward where it is steered, in units a second.
let shipSpeed: Float = 16
/// From the center to each corner of an enemy's octahedron.
let enemyRadius: Float = 0.8
/// Half the width of a bullet.
let bulletRadius: Float = 0.07
let bulletSpeed: Float = 60
let fireInterval: Float = 0.12
/// Where enemies appear, and where everything that flew past goes.
let farZ: Float = -90
let nearZ: Float = 6

enum EnemyKind {
    /// Flies straight ahead.
    case straight
    /// Turns toward the ship as it comes, at a limited rate.
    case homing
}

struct Enemy {
    var kind: EnemyKind
    var position: Vector3<Float>
    var velocity: Vector3<Float>
    /// How far it has spun about `spinAxis`, in radians.
    var spin: Float
    static let spinAxis = normalize(Vector3<Float>(0.3, 1, 0.2))

    /// Its orientation, which its shape for hits turns with.
    var rotation: Matrix4x4<Float> {
        .rotation(angle: spin, axis: Self.spinAxis)
    }

    /// The transform from world space, relative to its center, into its own
    /// space: the inverse of its rotation, which is the rotation's transpose.
    var inverseRotation: Matrix4x4<Float> {
        transpose(rotation)
    }

    /// Whether `point` is within its octahedron, made `margin` larger: within
    /// `enemyRadius + margin` of its center along the axes of its own space,
    /// summed. `inverseRotation` is its `inverseRotation`, which callers that
    /// test many points make once.
    func contains(_ point: Vector3<Float>, margin: Float = 0, inverseRotation: Matrix4x4<Float>) -> Bool {
        let offset = point - position
        let reach = enemyRadius + margin
        // Nothing beyond its corners can be inside.
        guard abs(offset.x) < reach, abs(offset.y) < reach, abs(offset.z) < reach else { return false }
        let local = (inverseRotation * Vector4(offset, 0)).xyz
        return abs(local.x) + abs(local.y) + abs(local.z) < reach
    }
}

/// A piece of a destroyed enemy, flying apart until its life runs out.
struct Debris {
    var position, velocity: Vector3<Float>
    var life: Float
}

/// A shooting game in 3D: the ship flies in a plane, firing ahead, and
/// enemies come at it from the distance, faster and more often over time,
/// more and more of them homing in on it.
struct ShooterState {
    var ship = Vector2<Float>.zero
    /// How fast the ship moves sideways, from -1 to 1, which tilts it.
    var bank: Float = 0
    var bullets: [Vector3<Float>] = []
    var enemies: [Enemy] = []
    var debris: [Debris] = []
    /// Stars and stripes on the floor, which stream past to show the speed.
    var stars: [Vector3<Float>] = (0..<160).map { _ in
        Vector3(Float.random(in: -40...40), Float.random(in: -20...25), Float.random(in: farZ...nearZ))
    }
    var stripes: [Float] = (0..<12).map { farZ + Float($0) * (nearZ - farZ) / 12 }
    var elapsed: Float = 0
    var score = 0
    var best = 0
    var isOver = false
    private var untilNextShot: Float = 0
    private var untilNextEnemy: Float = 1

    mutating func restart() {
        let (stars, stripes, best) = (self.stars, self.stripes, self.best)
        self = ShooterState()
        (self.stars, self.stripes, self.best) = (stars, stripes, best)
    }

    /// Advances the game by `duration` seconds, with the ship flying toward
    /// `target` in its plane, and firing while `fires`.
    mutating func tick(duration: Float, target: Vector2<Float>, fires: Bool) {
        let speed = 30 + elapsed * 0.5
        streamScenery(duration: duration, speed: speed)
        updateDebris(duration: duration)
        guard !isOver else { return }
        elapsed += duration

        let toTarget = clamp(target, -shipBounds, shipBounds) - ship
        let distance = length(toTarget)
        let step = min(distance, shipSpeed * duration)
        let move = distance > 0 ? toTarget / distance * step : .zero
        ship += move
        bank += (move.x / (shipSpeed * duration) - bank) * min(1, 10 * duration)

        untilNextShot -= duration
        if fires && untilNextShot <= 0 {
            // Two guns, one under each wing.
            for side: Float in [-0.45, 0.45] {
                bullets.append(Vector3(ship.x + side, ship.y - 0.1, -0.8))
            }
            untilNextShot = fireInterval
        }

        spawnEnemies(duration: duration)
        moveEnemies(duration: duration)
        shootEnemies(duration: duration)

        let shipPosition = Vector3(ship, 0)
        if enemies.contains(where: hits(shipAt: shipPosition)) {
            isOver = true
            best = max(best, score)
            explode(at: shipPosition, pieces: 40)
        }
        enemies.removeAll { $0.position.z > nearZ }
    }

    private mutating func spawnEnemies(duration: Float) {
        untilNextEnemy -= duration
        while untilNextEnemy <= 0 {
            let position = Vector3(
                Float.random(in: -shipBounds.x...shipBounds.x), Float.random(in: -shipBounds.y...shipBounds.y), farZ)
            // More of them home in as time goes on, up to half.
            let kind: EnemyKind = Float.random(in: 0..<1) < min(0.5, 0.1 + elapsed * 0.01) ? .homing : .straight
            let forward = Float.random(in: 14...(20 + elapsed * 0.8))
            enemies.append(Enemy(kind: kind, position: position, velocity: Vector3(0, 0, forward), spin: 0))
            untilNextEnemy += max(0.25, 1.1 - elapsed * 0.02)
        }
    }

    private mutating func moveEnemies(duration: Float) {
        for index in enemies.indices {
            if enemies[index].kind == .homing && enemies[index].position.z < -4 {
                // Sideways toward the ship, at a speed that grows only so
                // fast, so that a quick swerve still loses it.
                let offset = ship - enemies[index].position.xy
                let wanted = length(offset) > 0 ? normalize(offset) * 7 : .zero
                let sideways = enemies[index].velocity.xy
                let change = wanted - sideways
                let most = 9 * duration
                let turn = length(change) > most ? normalize(change) * most : change
                enemies[index].velocity += Vector3(turn, 0)
            }
            enemies[index].position += enemies[index].velocity * duration
            enemies[index].spin += 2 * duration
        }
    }

    // A bullet moves far in one tick, so it hits what it passes through along
    // the way as well as what it ends in.
    private mutating func shootEnemies(duration: Float) {
        let travel = bulletSpeed * duration
        let steps = Int((travel / 0.2).rounded(.up))
        var survivors: [Enemy] = []
        let reach = enemyRadius + bulletRadius
        for enemy in enemies {
            let inverseRotation = enemy.inverseRotation
            let (x, y, z) = (enemy.position.x, enemy.position.y, enemy.position.z)
            let hit = bullets.firstIndex { bullet in
                // Most bullets are far from most enemies, which scalars tell
                // quickly, as vectors take long in unoptimized builds, as in
                // the browser.
                guard abs(bullet.x - x) < reach, abs(bullet.y - y) < reach,
                    z > bullet.z - travel - reach, z < bullet.z + reach
                else { return false }
                return (0...steps).contains { step in
                    let point = bullet - Vector3(0, 0, travel * Float(step) / Float(steps))
                    return enemy.contains(point, margin: bulletRadius, inverseRotation: inverseRotation)
                }
            }
            if let hit {
                bullets.remove(at: hit)
                score += enemy.kind == .homing ? 200 : 100
                explode(at: enemy.position, pieces: 14)
            } else {
                survivors.append(enemy)
            }
        }
        enemies = survivors
        bullets = bullets.map { $0 - Vector3(0, 0, travel) }.filter { $0.z > farZ }
    }

    /// Whether an enemy touches the ship at `shipPosition`: whether the
    /// enemy's octahedron reaches the ship's box.
    private func hits(shipAt shipPosition: Vector3<Float>) -> (Enemy) -> Bool {
        { enemy in
            // The point of the box nearest the enemy's center is a good
            // stand-in for where they would touch, as the box is small.
            let nearest = clamp(enemy.position, shipPosition - shipHalfExtent, shipPosition + shipHalfExtent)
            return enemy.contains(nearest, inverseRotation: enemy.inverseRotation)
        }
    }

    private mutating func explode(at position: Vector3<Float>, pieces: Int) {
        for _ in 0..<pieces {
            let direction = normalize(
                Vector3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) + 0.001)
            debris.append(Debris(position: position, velocity: direction * Float.random(in: 3...12), life: 1))
        }
    }

    private mutating func updateDebris(duration: Float) {
        for index in debris.indices {
            debris[index].position += debris[index].velocity * duration
            debris[index].velocity *= 1 - 2 * duration
            debris[index].life -= duration * 1.5
        }
        debris.removeAll { $0.life <= 0 }
    }

    private mutating func streamScenery(duration: Float, speed: Float) {
        let depth = nearZ - farZ
        for index in stars.indices {
            stars[index].z += speed * duration
            if stars[index].z > nearZ { stars[index].z -= depth }
        }
        for index in stripes.indices {
            stripes[index] += speed * duration
            if stripes[index] > nearZ { stripes[index] -= depth }
        }
    }
}
