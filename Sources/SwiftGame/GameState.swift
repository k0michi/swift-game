import GameToolkit
import RealModule
import VectorMath

// Game coordinates are window points with the origin at the top left.
let fieldWidth: Float = 800
let fieldHeight: Float = 480
let fieldSize = Vector2(fieldWidth, fieldHeight)
let playerRadius: Float = 7
let bulletRadius: Float = 6

// The game advances in fixed ticks, independent of the display frame rate.
let ticksPerSecond: Float = 60
let tickDuration = 1 / ticksPerSecond

struct Bullet {
    var position, velocity: Vector2<Float>
    // Position at the previous tick, for interpolating between ticks when drawing.
    var previousPosition: Vector2<Float>
}

struct GameState {
    var player = fieldSize / 2
    var bullets: [Bullet] = []
    var elapsed: Float = 0
    var untilNextSpawn: Float = 1
    var isOver = false
    var best: Float = 0
    // The strongest collision between bullets since the frame last played a
    // sound for one: how fast they approached, and where.
    var strongestBounce: (speed: Float, x: Float)?

    mutating func restart() {
        bullets = []
        elapsed = 0
        untilNextSpawn = 1
        isOver = false
    }

    // Bullets enter from a random edge, aimed roughly at the player.
    // They come faster and more often the longer the player survives.
    mutating func spawnBullet() {
        let position =
            switch Int.random(in: 0..<4) {
            case 0: Vector2(Float.random(in: 0...fieldWidth), -bulletRadius)
            case 1: Vector2(Float.random(in: 0...fieldWidth), fieldHeight + bulletRadius)
            case 2: Vector2(-bulletRadius, Float.random(in: 0...fieldHeight))
            default: Vector2(fieldWidth + bulletRadius, Float.random(in: 0...fieldHeight))
            }
        let toPlayer = player - position
        let angle = Float.atan2(y: toPlayer.y, x: toPlayer.x) + Float.random(in: -0.35...0.35)
        let speed = Float.random(in: 120...(180 + elapsed * 6))
        bullets.append(
            Bullet(
                position: position, velocity: Vector2(Float.cos(angle), Float.sin(angle)) * speed,
                previousPosition: position))
    }

    // Equal-mass elastic collisions: overlapping balls are pushed apart and
    // swap their velocity components along the line between their centers.
    mutating func collideBullets() {
        let minimumDistance = bulletRadius * 2
        for i in bullets.indices {
            for j in (i + 1)..<bullets.count {
                let offset = bullets[j].position - bullets[i].position
                let distanceSquared = dot(offset, offset)
                guard distanceSquared < minimumDistance * minimumDistance, distanceSquared > 0
                else { continue }
                let distance = distanceSquared.squareRoot()
                let normal = offset / distance
                let push = normal * (minimumDistance - distance) / 2
                bullets[i].position -= push
                bullets[j].position += push
                let approach = dot(bullets[j].velocity - bullets[i].velocity, normal)
                if approach < 0 {
                    if -approach > strongestBounce?.speed ?? 0 {
                        strongestBounce = (-approach, (bullets[i].position.x + bullets[j].position.x) / 2)
                    }
                    bullets[i].velocity += normal * approach
                    bullets[j].velocity -= normal * approach
                }
            }
        }
    }

    mutating func tick() {
        guard !isOver else { return }
        elapsed += tickDuration
        untilNextSpawn -= tickDuration
        while untilNextSpawn <= 0 {
            spawnBullet()
            untilNextSpawn += max(0.08, 0.5 - elapsed * 0.012)
        }

        for index in bullets.indices {
            bullets[index].previousPosition = bullets[index].position
            bullets[index].position += bullets[index].velocity * tickDuration
        }
        collideBullets()

        let margin = bulletRadius * 2
        let hitDistance = playerRadius + bulletRadius - 2
        for bullet in bullets {
            let offset = bullet.position - player
            if dot(offset, offset) < hitDistance * hitDistance {
                isOver = true
            }
        }
        bullets.removeAll {
            any(($0.position < Vector2(repeating: -margin)) | ($0.position > fieldSize + margin))
        }

        if isOver {
            best = max(best, elapsed)
            print(
                "Game over: survived \(formatTenths(elapsed)) s (best \(formatTenths(best)) s). Click to retry."
            )
        }
    }
}
