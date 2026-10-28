import Foundation

// Game coordinates are window points with the origin at the top left.
let fieldWidth: Float = 800
let fieldHeight: Float = 480
let playerRadius: Float = 7
let bulletRadius: Float = 6

// The game advances in fixed ticks, independent of the display frame rate.
let ticksPerSecond: Float = 60
let tickDuration = 1 / ticksPerSecond

struct Bullet {
    var x, y, vx, vy: Float
    // Position at the previous tick, for interpolating between ticks when drawing.
    var previousX, previousY: Float
}

struct Game {
    var playerX = fieldWidth / 2
    var playerY = fieldHeight / 2
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
        let x, y: Float
        switch Int.random(in: 0..<4) {
        case 0: (x, y) = (Float.random(in: 0...fieldWidth), -bulletRadius)
        case 1: (x, y) = (Float.random(in: 0...fieldWidth), fieldHeight + bulletRadius)
        case 2: (x, y) = (-bulletRadius, Float.random(in: 0...fieldHeight))
        default: (x, y) = (fieldWidth + bulletRadius, Float.random(in: 0...fieldHeight))
        }
        let angle = atan2(playerY - y, playerX - x) + Float.random(in: -0.35...0.35)
        let speed = Float.random(in: 120...(180 + elapsed * 6))
        bullets.append(
            Bullet(
                x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed, previousX: x,
                previousY: y
            ))
    }

    // Equal-mass elastic collisions: overlapping balls are pushed apart and
    // swap their velocity components along the line between their centers.
    mutating func collideBullets() {
        let minimumDistance = bulletRadius * 2
        for i in bullets.indices {
            for j in (i + 1)..<bullets.count {
                let dx = bullets[j].x - bullets[i].x
                let dy = bullets[j].y - bullets[i].y
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared < minimumDistance * minimumDistance, distanceSquared > 0
                else { continue }
                let distance = distanceSquared.squareRoot()
                let nx = dx / distance
                let ny = dy / distance
                let push = (minimumDistance - distance) / 2
                bullets[i].x -= nx * push
                bullets[i].y -= ny * push
                bullets[j].x += nx * push
                bullets[j].y += ny * push
                let approach =
                    (bullets[j].vx - bullets[i].vx) * nx + (bullets[j].vy - bullets[i].vy) * ny
                if approach < 0 {
                    if -approach > strongestBounce?.speed ?? 0 {
                        strongestBounce = (-approach, (bullets[i].x + bullets[j].x) / 2)
                    }
                    bullets[i].vx += approach * nx
                    bullets[i].vy += approach * ny
                    bullets[j].vx -= approach * nx
                    bullets[j].vy -= approach * ny
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
            bullets[index].previousX = bullets[index].x
            bullets[index].previousY = bullets[index].y
            bullets[index].x += bullets[index].vx * tickDuration
            bullets[index].y += bullets[index].vy * tickDuration
        }
        collideBullets()

        let margin = bulletRadius * 2
        let hitDistance = playerRadius + bulletRadius - 2
        for bullet in bullets {
            let dx = bullet.x - playerX
            let dy = bullet.y - playerY
            if dx * dx + dy * dy < hitDistance * hitDistance {
                isOver = true
            }
        }
        bullets.removeAll {
            $0.x < -margin || $0.x > fieldWidth + margin || $0.y < -margin
                || $0.y > fieldHeight + margin
        }

        if isOver {
            best = max(best, elapsed)
            print(
                "Game over: survived \(formatTenths(elapsed)) s (best \(formatTenths(best)) s). Click to retry."
            )
        }
    }
}

/// `value` with one decimal place, rounded down.
func formatTenths(_ value: Float) -> String {
    let tenths = Int(value * 10)
    return "\(tenths / 10).\(tenths % 10)"
}
