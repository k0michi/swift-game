import Testing
import VectorMath

@testable import Shooter

/// A game with only `enemy` in it, which ticks no more enemies in for a while.
private func state(with enemy: Enemy) -> ShooterState {
    var state = ShooterState()
    state.enemies = [enemy]
    return state
}

private func enemy(at position: Vector3<Float>, kind: EnemyKind = .straight, forward: Float = 0) -> Enemy {
    Enemy(kind: kind, position: position, velocity: Vector3(0, 0, forward), spin: 0)
}

@Test func aBulletHitsAnEnemyItPassesThrough() {
    // The enemy is between where the bullet is and where it will be after a
    // tick, a unit further.
    var game = state(with: enemy(at: Vector3(0.45, -0.1, -10.5)))
    game.bullets = [Vector3(0.45, -0.1, -10)]
    game.tick(duration: 1 / 60, target: Vector2(0, 0), fires: false)
    #expect(game.enemies.isEmpty)
    #expect(game.score == 100)
}

@Test func aBulletMissesAnEnemyBesideIt() {
    var game = state(with: enemy(at: Vector3(2, -0.1, -10.5)))
    game.bullets = [Vector3(0.45, -0.1, -10)]
    game.tick(duration: 1 / 60, target: Vector2(0, 0), fires: false)
    #expect(game.enemies.count == 1)
    #expect(game.score == 0)
}

@Test(arguments: [Float(-1.1), 1.1])
func anEnemyPassingAboveOrBelowTheShipMissesIt(height: Float) {
    // Farther above or below than half the ship's height and the enemy's
    // reach together, though within the old sphere's.
    var game = state(with: enemy(at: Vector3(0, height, 0)))
    game.tick(duration: 1 / 60, target: Vector2(0, 0), fires: false)
    #expect(!game.isOver)
}

@Test(arguments: [Vector3<Float>(0, -0.9, 0), Vector3(1.2, 0, 0), Vector3(0, 0, -1.6)])
func anEnemyTouchingTheShipHitsIt(offset: Vector3<Float>) {
    var game = state(with: enemy(at: offset))
    game.tick(duration: 1 / 60, target: Vector2(0, 0), fires: false)
    #expect(game.isOver)
}

@Test func aHomingEnemyTurnsTowardTheShip() {
    var game = state(with: enemy(at: Vector3(4, 2, -60), kind: .homing, forward: 20))
    game.ship = Vector2(-3, -2)
    for _ in 0..<30 {
        game.tick(duration: 1 / 60, target: game.ship, fires: false)
    }
    let homing = game.enemies.first { $0.kind == .homing }!
    #expect(homing.velocity.x < 0)
    #expect(homing.velocity.y < 0)
}

@Test func theShipFliesToItsTargetAtLimitedSpeed() {
    var game = ShooterState()
    game.tick(duration: 1 / 60, target: Vector2(5, 0), fires: false)
    #expect(abs(game.ship.x - shipSpeed / 60) < 0.0001)
    for _ in 0..<60 {
        game.tick(duration: 1 / 60, target: Vector2(5, 0), fires: false)
    }
    #expect(abs(game.ship.x - 5) < 0.0001)
}
