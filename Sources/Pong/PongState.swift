import RealModule
import VectorMath

let fieldSize = Vector2<Float>(800, 480)
let paddleSize = Vector2<Float>(12, 80)
let paddleX: Float = 30
let ballRadius: Float = 7
let winningScore = 7

let playerSpeed: Float = 1200
let computerSpeed: Float = 330
let serveSpeed: Float = 360
let topSpeed: Float = 900

enum Side {
    case player, computer
}

enum Event: Equatable {
    case hit, wall, point(Side)
}

struct PongState {
    var playerY = fieldSize.y / 2
    var computerY = fieldSize.y / 2
    var ball = fieldSize / 2
    var previousBall = fieldSize / 2
    var velocity = Vector2<Float>.zero
    var playerScore = 0
    var computerScore = 0
    var untilServe: Float = 1
    var serveDirection: Float = 1
    var events: [Event] = []

    var winner: Side? {
        if playerScore >= winningScore { return .player }
        if computerScore >= winningScore { return .computer }
        return nil
    }

    mutating func tick(duration: Float, playerTarget: Float) {
        previousBall = ball
        playerY = approach(playerY, playerTarget, by: playerSpeed * duration)
        let computerTarget = velocity.x > 0 ? ball.y : fieldSize.y / 2
        computerY = approach(computerY, computerTarget, by: computerSpeed * duration)
        guard winner == nil else { return }

        if untilServe > 0 {
            untilServe -= duration
            if untilServe <= 0 {
                velocity = Vector2(serveDirection * serveSpeed, Float.random(in: -150...150))
            }
            return
        }

        var next = ball + velocity * duration
        if next.y < ballRadius || next.y > fieldSize.y - ballRadius {
            velocity.y = -velocity.y
            next.y = min(max(next.y, ballRadius), fieldSize.y - ballRadius)
            events.append(.wall)
        }

        let reach = paddleX + paddleSize.x / 2 + ballRadius
        if velocity.x < 0, ball.x >= reach, next.x < reach, abs(next.y - playerY) < paddleSize.y / 2 + ballRadius {
            next.x = reach
            returnBall(from: playerY, direction: 1)
        } else if velocity.x > 0, ball.x <= fieldSize.x - reach, next.x > fieldSize.x - reach,
            abs(next.y - computerY) < paddleSize.y / 2 + ballRadius
        {
            next.x = fieldSize.x - reach
            returnBall(from: computerY, direction: -1)
        }
        ball = next

        if ball.x < 0 {
            score(.computer)
        } else if ball.x > fieldSize.x {
            score(.player)
        }
    }

    private mutating func returnBall(from paddleY: Float, direction: Float) {
        let offset = (ball.y - paddleY) / (paddleSize.y / 2 + ballRadius)
        let angle = offset * Float.pi / 3
        let speed = min(length(velocity) * 1.06, topSpeed)
        velocity = Vector2(direction * Float.cos(angle), Float.sin(angle)) * speed
        events.append(.hit)
    }

    private mutating func score(_ side: Side) {
        if side == .player { playerScore += 1 } else { computerScore += 1 }
        ball = fieldSize / 2
        previousBall = ball
        velocity = .zero
        untilServe = 1
        serveDirection = side == .player ? 1 : -1
        events.append(.point(side))
    }

    private func approach(_ y: Float, _ target: Float, by step: Float) -> Float {
        let target = min(max(target, paddleSize.y / 2), fieldSize.y - paddleSize.y / 2)
        return y + min(max(target - y, -step), step)
    }
}
