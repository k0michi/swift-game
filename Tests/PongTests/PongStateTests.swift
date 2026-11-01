import Testing
import VectorMath

@testable import Pong

private let tick: Float = 1 / 60

private func served(ball: Vector2<Float>, velocity: Vector2<Float>) -> PongState {
    var game = PongState()
    game.untilServe = 0
    game.ball = ball
    game.velocity = velocity
    return game
}

@Suite("PongState")
struct PongStateTests {
    @Test
    func servesAfterASecond() {
        var game = PongState()
        game.tick(duration: 0.5, playerTarget: game.playerY)
        #expect(game.velocity == .zero)
        game.tick(duration: 0.6, playerTarget: game.playerY)
        #expect(game.velocity.x == serveSpeed)
    }

    @Test
    func bouncesOffTheWalls() {
        var game = served(ball: Vector2(400, ballRadius + 1), velocity: Vector2(0, -300))
        game.tick(duration: tick, playerTarget: game.playerY)
        #expect(game.velocity.y > 0)
        #expect(game.events == [.wall])
    }

    @Test
    func aPaddleReturnsTheBall() {
        var game = served(ball: Vector2(paddleX + 20, fieldSize.y / 2), velocity: Vector2(-600, 0))
        game.tick(duration: tick, playerTarget: game.playerY)
        #expect(game.velocity.x > 0)
        #expect(abs(game.velocity.y) < 0.01)
        #expect(game.events == [.hit])
    }

    @Test
    func theEndOfAPaddleReturnsTheBallSteeply() {
        let y = fieldSize.y / 2 + paddleSize.y / 2
        var game = served(ball: Vector2(paddleX + 20, y), velocity: Vector2(-600, 0))
        game.tick(duration: tick, playerTarget: game.playerY)
        #expect(game.velocity.x > 0)
        #expect(game.velocity.y > game.velocity.x)
    }

    @Test
    func aMissIsAPointToTheOther() {
        var game = served(ball: Vector2(10, 20), velocity: Vector2(-900, 0))
        game.tick(duration: tick, playerTarget: fieldSize.y)
        #expect(game.computerScore == 1)
        #expect(game.events == [.point(.computer)])
        game.tick(duration: 1, playerTarget: game.playerY)
        #expect(game.velocity.x < 0)
    }

    @Test
    func theFirstToSevenWins() {
        var game = served(ball: Vector2(fieldSize.x - 5, 20), velocity: Vector2(900, 0))
        game.playerScore = winningScore - 1
        game.tick(duration: tick, playerTarget: game.playerY)
        #expect(game.winner == .player)
        game.tick(duration: 5, playerTarget: game.playerY)
        #expect(game.velocity == .zero)
    }

    @Test
    func theComputerIsSlowerThanThePlayer() {
        var game = served(ball: Vector2(400, 0), velocity: Vector2(300, 0))
        game.tick(duration: 0.1, playerTarget: 0)
        #expect(fieldSize.y / 2 - game.playerY == playerSpeed * 0.1)
        #expect(fieldSize.y / 2 - game.computerY == computerSpeed * 0.1)
    }
}
