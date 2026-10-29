import Foundation
import Testing
import VectorMath

@Suite("Vector")
struct VectorTests {
    @Test
    func layoutIsPackedComponents() {
        #expect(MemoryLayout<Vector2<Float>>.size == 8)
        #expect(MemoryLayout<Vector3<Float>>.size == 12)
        #expect(MemoryLayout<Vector3<Float>>.stride == 12)
        #expect(MemoryLayout<Vector3<Float>>.alignment == 4)
        #expect(MemoryLayout<Vector4<Float>>.size == 16)
        #expect(MemoryLayout<Vector3<Double>>.stride == 24)
        #expect(MemoryLayout<Vector3<UInt8>>.stride == 3)
        #expect(MemoryLayout<Vector4<Bool>>.stride == 4)
        #expect(MemoryLayout<Vector4<Float>>.offset(of: \.w) == 12)

        let vectors = [Vector3<Float>(1, 2, 3), Vector3(4, 5, 6)]
        let scalars = vectors.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(scalars == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func initializersTakeComponentsInOrder() {
        #expect(Vector3(x: 1, y: 2, z: 3) == Vector3(1, 2, 3))
        #expect(Vector3(repeating: 7) == Vector3(7, 7, 7))
        #expect(Vector3(1, Vector2(2, 3)) == Vector3(1, 2, 3))
        #expect(Vector3(Vector2(1, 2), 3) == Vector3(1, 2, 3))
        #expect(Vector4(Vector3(1, 2, 3), 4) == Vector4(1, 2, 3, 4))
        #expect(Vector4(1, Vector3(2, 3, 4)) == Vector4(1, 2, 3, 4))
        #expect(Vector4(Vector2(1, 2), Vector2(3, 4)) == Vector4(1, 2, 3, 4))
        #expect(Vector4(Vector2(1, 2), 3, 4) == Vector4(1, 2, 3, 4))
        #expect(Vector4(1, Vector2(2, 3), 4) == Vector4(1, 2, 3, 4))
        #expect(Vector4(1, 2, Vector2(3, 4)) == Vector4(1, 2, 3, 4))
    }

    @Test
    func subscriptReadsAndWritesComponents() {
        var vector = Vector4(1, 2, 3, 4)
        #expect((0..<Vector4<Int>.scalarCount).map { vector[$0] } == [1, 2, 3, 4])
        vector[2] = 9
        #expect(vector == Vector4(1, 2, 9, 4))
    }

    @Test
    func colorNamesAliasComponents() {
        var color = Vector4<Float>(0.1, 0.2, 0.3, 0.4)
        #expect(color.r == color.x && color.g == color.y && color.b == color.z && color.a == color.w)
        color.a = 1
        #expect(color.w == 1)
    }

    @Test
    func swizzlesPickComponents() {
        let vector = Vector4(1, 2, 3, 4)
        #expect(vector.xy == Vector2(1, 2))
        #expect(vector.wzyx == Vector4(4, 3, 2, 1))
        #expect(vector.zzx == Vector3(3, 3, 1))
        #expect(vector.bgr == Vector3(3, 2, 1))
        #expect(vector.aaaa == Vector4(repeating: 4))
        #expect(Vector2(5, 6).yxyx == Vector4(6, 5, 6, 5))
    }

    @Test
    func arithmeticIsComponentwise() {
        let a = Vector3(1, 2, 3)
        let b = Vector3(4, 5, 6)
        #expect(a + b == Vector3(5, 7, 9))
        #expect(b - a == Vector3(3, 3, 3))
        #expect(a * b == Vector3(4, 10, 18))
        #expect(a * 2 == Vector3(2, 4, 6))
        #expect(2 * a == Vector3(2, 4, 6))
        #expect(a + 1 == Vector3(2, 3, 4))
        #expect(10 - a == Vector3(9, 8, 7))
        #expect(-a == Vector3(-1, -2, -3))
        #expect(Vector3<Int>.zero == Vector3(0, 0, 0))

        var c = a
        c += b
        c *= 2
        c -= 1
        #expect(c == Vector3(9, 13, 17))
    }

    @Test
    func divisionFollowsTheScalarType() {
        #expect(Vector2(7, -7) / 2 == Vector2(3, -3))
        #expect(Vector2(7, -7) % 2 == Vector2(1, -1))
        #expect(Vector2<Float>(7, -7) / 2 == Vector2(3.5, -3.5))
        #expect(Vector2<Float>(7.5, -7.5) % 2 == Vector2(1.5, -1.5))
        #expect(1 / Vector2<Double>(2, 4) == Vector2(0.5, 0.25))
    }

    @Test
    func integerVectorsHaveBitwiseAndWrappingOperators() {
        let a = Vector2<UInt8>(0b1100, 255)
        let b = Vector2<UInt8>(0b1010, 1)
        #expect(a & b == Vector2(0b1000, 1))
        #expect(a | b == Vector2(0b1110, 255))
        #expect(a ^ b == Vector2(0b0110, 254))
        #expect(~b == Vector2(0b1111_0101, 254))
        #expect(b << 1 == Vector2(0b10100, 2))
        #expect(a >> Vector2(2, 4) == Vector2(0b11, 15))
        #expect(a &+ b == Vector2(0b10110, 0))
        #expect(Vector2<UInt8>(0, 1) &- 1 == Vector2(255, 0))
        #expect(Vector2<UInt8>(128, 3) &* 2 == Vector2(0, 6))
    }

    @Test
    func comparisonsReturnBoolVectors() {
        let a = Vector3(1, 2, 3)
        let b = Vector3(3, 2, 1)
        let equal = a == b
        #expect(type(of: equal) == Vector3<Bool>.self)
        #expect(equal == Vector3(false, true, false))
        #expect((a != b) == Vector3(true, false, true))
        #expect((a < b) == Vector3(true, false, false))
        #expect((a <= b) == Vector3(true, true, false))
        #expect((a > b) == Vector3(false, false, true))
        #expect((a >= b) == Vector3(false, true, true))
    }

    @Test
    func equalityInConditionsIsWholeVector() {
        let a = Vector2<Float>(1, 2)
        if a == Vector2(1, 2) {
        } else {
            Issue.record("== in a condition should compare the whole vector")
        }
        #expect(a != Vector2(1, 3))
        #expect(a == Vector2(1, 2) ? true : false)
        #expect([a, Vector2(3, 4)].contains(Vector2(3, 4)))
        #expect(Set([a, a, Vector2(0, 0)]).count == 2)
    }

    @Test
    func boolVectorsHaveLogicalOperators() {
        let a = Vector4(true, true, false, false)
        let b = Vector4(true, false, true, false)
        #expect((a & b) == Vector4(true, false, false, false))
        #expect((a | b) == Vector4(true, true, true, false))
        #expect(!a == Vector4(false, false, true, true))
    }

    @Test
    func conversionsChangeTheScalarType() {
        #expect(Vector2<Float>(Vector2<Int>(1, -2)) == Vector2(1, -2))
        #expect(Vector2<Int>(Vector2<Double>(1.9, -1.9)) == Vector2(1, -1))
        #expect(Vector2<Int64>(Vector2<UInt8>(255, 0)) == Vector2(255, 0))
        #expect(Vector2<Double>(Vector2<Float>(0.5, 2)) == Vector2(0.5, 2))
    }

    @Test
    func codableAsAnArrayOfComponents() throws {
        let vector = Vector3<Int>(1, 2, 3)
        let data = try JSONEncoder().encode(vector)
        #expect(String(decoding: data, as: UTF8.self) == "[1,2,3]")
        #expect(try JSONDecoder().decode(Vector3<Int>.self, from: data) == vector)
    }

    @Test
    func descriptionListsComponents() {
        #expect(Vector3(1, 2, 3).description == "Vector3(1, 2, 3)")
    }
}
