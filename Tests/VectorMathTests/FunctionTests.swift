import Testing
import VectorMath

@Suite("Built-in functions")
struct FunctionTests {
    @Test
    func standardLibraryFunctionsStillResolve() {
        #expect(min(1, 2) == 1)
        #expect(max(1.5, 2.5) == 2.5)
        #expect(abs(-3) == 3)
    }

    @Test
    func logicalFunctions() {
        #expect(all(Vector3(true, true, true)))
        #expect(!all(Vector3(true, false, true)))
        #expect(any(Vector2(false, true)))
        #expect(!any(Vector4(repeating: false)))
        #expect(all(Vector3(1, 2, 3) == Vector3(1, 2, 3)))
        #expect(
            select(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(true, false, true)) == Vector3(4, 2, 6))
        #expect(select(Vector2(1, 2), Vector2(3, 4), true) == Vector2(3, 4))
        #expect(select(1, 2, false) == 1)
    }

    @Test
    func componentwiseNumericFunctions() {
        let e = Vector4<Double>(-1.5, -0.5, 0.5, 2.5)
        #expect(abs(e) == Vector4(1.5, 0.5, 0.5, 2.5))
        #expect(sign(e) == Vector4(-1, -1, 1, 1))
        #expect(sign(Vector2<Int>(0, -4)) == Vector2(0, -1))
        #expect(floor(e) == Vector4(-2, -1, 0, 2))
        #expect(ceil(e) == Vector4(-1, -0, 1, 3))
        #expect(round(e) == Vector4(-2, -0, 0, 2))
        #expect(trunc(e) == Vector4(-1, -0, 0, 2))
        #expect(fract(e) == Vector4(0.5, 0.5, 0.5, 0.5))
        #expect(min(Vector2(1, 5), Vector2(3, 2)) == Vector2(1, 2))
        #expect(max(Vector2(1, 5), Vector2(3, 2)) == Vector2(3, 5))
        #expect(
            clamp(Vector3(-1, 5, 10), Vector3(repeating: 0), Vector3(repeating: 8)) == Vector3(0, 5, 8))
        #expect(saturate(e) == Vector4(0, 0, 0.5, 1))
        #expect(sqrt(Vector2<Float>(4, 9)) == Vector2(2, 3))
        #expect(inverseSqrt(Vector2<Float>(4, 16)) == Vector2(0.5, 0.25))
        #expect(step(Vector2<Float>(1, 1), Vector2(0.5, 1)) == Vector2(0, 1))
        #expect(smoothstep(Vector2<Float>(0, 0), Vector2(2, 2), Vector2(1, 3)) == Vector2(0.5, 1))
        #expect(mix(Vector2<Float>(0, 10), Vector2(10, 20), 0.5) == Vector2(5, 15))
        #expect(
            mix(Vector2<Float>(0, 10), Vector2(10, 20), Vector2(0, 1)) == Vector2(0, 20))
        #expect(
            fma(Vector2<Double>(2, 3), Vector2(4, 5), Vector2(1, 1)) == Vector2(9, 16))
        #expect(degrees(Vector2<Double>(.pi, .pi / 2)) == Vector2(180, 90))
        #expect(radians(Vector2<Double>(180, 90)) == Vector2(.pi, .pi / 2))
    }

    @Test
    func geometricFunctions() {
        #expect(dot(Vector3(1, 2, 3), Vector3(4, 5, 6)) == 32)
        #expect(cross(Vector3(1, 0, 0), Vector3(0, 1, 0)) == Vector3(0, 0, 1))
        #expect(length(Vector2<Float>(3, 4)) == 5)
        #expect(distance(Vector2<Float>(1, 1), Vector2(4, 5)) == 5)
        #expect(normalize(Vector2<Float>(0, 3)) == Vector2(0, 1))
        #expect(reflect(Vector2<Float>(1, -1), Vector2(0, 1)) == Vector2(1, 1))
        #expect(faceForward(Vector2<Float>(0, 1), Vector2(1, 0), Vector2(-1, 0)) == Vector2(0, 1))
        #expect(faceForward(Vector2<Float>(0, 1), Vector2(1, 0), Vector2(1, 0)) == Vector2(0, -1))
        // Straight through when the indices match, nothing past the critical angle.
        let incident = normalize(Vector2<Double>(1, -1))
        #expect(refract(incident, Vector2(0, 1), 1) == incident)
        #expect(refract(incident, Vector2(0, 1), 2) == .zero)
    }

    @Test
    func scalarFunctions() {
        #expect(clamp(5, 0, 3) == 3)
        #expect(sign(-2.5) == -1)
        #expect(fract(-0.25) == 0.75)
        #expect(saturate(1.5) == 1)
        #expect(mix(2.0, 4.0, 0.25) == 2.5)
        #expect(smoothstep(0.0, 1.0, 0.5) == 0.5)
    }
}
