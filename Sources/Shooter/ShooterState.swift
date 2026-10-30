import Foundation
import VectorMath

// The world is in units, with y up and the enemies coming from far down -z
// toward the ship, which flies in the plane z = 0.

/// How far the ship can move from the middle of the plane.
let shipBounds = Vector2<Float>(6, 3.5)
let shipRadius: Float = 0.6
let enemyRadius: Float = 0.8
let bulletSpeed: Float = 60
let fireInterval: Float = 0.12
/// Where enemies appear, and where everything that flew past goes.
let farZ: Float = -90
let nearZ: Float = 6

struct Enemy {
    var position: Vector3<Float>
    var speed: Float
    /// How far it has spun, in radians.
    var spin: Float
}

/// A piece of a destroyed enemy, flying apart until its life runs out.
struct Debris {
    var position, velocity: Vector3<Float>
    var life: Float
}

/// A shooting game in 3D: the ship flies in a plane, firing ahead, and
/// enemies come at it from the distance, faster and more often over time.
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

    /// Advances the game by `duration` seconds, with the ship steered in
    /// `direction`, each component from -1 to 1, and firing while `fires`.
    mutating func tick(duration: Float, direction: Vector2<Float>, fires: Bool) {
        let speed = 30 + elapsed * 0.5
        streamScenery(duration: duration, speed: speed)
        updateDebris(duration: duration)
        guard !isOver else { return }
        elapsed += duration

        ship = clamp(ship + direction * 9 * duration, -shipBounds, shipBounds)
        bank += (direction.x - bank) * min(1, 10 * duration)

        untilNextShot -= duration
        if fires && untilNextShot <= 0 {
            // Two guns, one under each wing.
            for side: Float in [-0.45, 0.45] {
                bullets.append(Vector3(ship.x + side, ship.y - 0.1, -0.8))
            }
            untilNextShot = fireInterval
        }
        bullets = bullets.map { $0 - Vector3(0, 0, bulletSpeed * duration) }.filter { $0.z > farZ }

        untilNextEnemy -= duration
        while untilNextEnemy <= 0 {
            enemies.append(
                Enemy(
                    position: Vector3(
                        Float.random(in: -shipBounds.x...shipBounds.x), Float.random(in: -shipBounds.y...shipBounds.y),
                        farZ),
                    speed: Float.random(in: 14...(20 + elapsed * 0.8)), spin: 0))
            untilNextEnemy += max(0.25, 1.1 - elapsed * 0.02)
        }
        for index in enemies.indices {
            enemies[index].position.z += enemies[index].speed * duration
            enemies[index].spin += 2 * duration
        }

        shootEnemies()
        let shipPosition = Vector3(ship, 0)
        if enemies.contains(where: { distance($0.position, shipPosition) < shipRadius + enemyRadius }) {
            isOver = true
            best = max(best, score)
            explode(at: shipPosition, pieces: 40)
        }
        enemies.removeAll { $0.position.z > nearZ }
    }

    private mutating func shootEnemies() {
        var survivors: [Enemy] = []
        for enemy in enemies {
            // A bullet moves far in one tick, so it hits what it passed through
            // along z as well as what it is in.
            if let hit = bullets.firstIndex(where: { bullet in
                length((bullet - enemy.position) * Vector3(1, 1, 0.4)) < enemyRadius + 0.2
            }) {
                bullets.remove(at: hit)
                score += 100
                explode(at: enemy.position, pieces: 14)
            } else {
                survivors.append(enemy)
            }
        }
        enemies = survivors
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
