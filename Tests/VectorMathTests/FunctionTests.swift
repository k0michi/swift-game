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
        #expect(floor(-1.5) == -2)
        #expect(ceil(-1.5) == -1)
        #expect(trunc(-1.5) == -1)
        #expect(sqrt(Float(9)) == 3)
        #expect(round(2.5) == 2)
        #expect(round(3.5) == 4)
        #expect(round(-0.5) == 0 && round(-0.5).sign == .minus)
        #expect(round(Float(1.25)) == 1)
        #expect(saturate(1.5) == 1)
        #expect(mix(2.0, 4.0, 0.25) == 2.5)
        #expect(smoothstep(0.0, 1.0, 0.5) == 0.5)
    }
}

@Suite("Transcendental built-in functions")
struct TranscendentalFunctionTests {
    @Test
    func applyToEachComponent() {
        let angles = Vector2<Double>(0, .pi / 2)
        expectClose(sin(angles), Vector2(0, 1))
        expectClose(cos(angles), Vector2(1, 0))
        expectClose(tan(Vector2<Double>(0, .pi / 4)), Vector2(0, 1))
        expectClose(asin(Vector2<Double>(0, 1)), angles)
        expectClose(acos(Vector2<Double>(1, 0)), angles)
        expectClose(atan(Vector2<Double>(0, 1)), Vector2(0, .pi / 4))
        expectClose(atan2(Vector2<Double>(1, -1), Vector2(0, 0)), Vector2(.pi / 2, -.pi / 2))
        expectClose(sinh(Vector2<Double>(0, 1)), Vector2(0, 1.1752011936438014))
        expectClose(cosh(Vector2<Double>(0, 1)), Vector2(1, 1.5430806348152437))
        expectClose(tanh(Vector2<Double>(0, 1)), Vector2(0, 0.7615941559557649))
        expectClose(asinh(Vector2<Double>(0, 1.1752011936438014)), Vector2(0, 1))
        expectClose(acosh(Vector2<Double>(1, 1.5430806348152437)), Vector2(0, 1))
        expectClose(atanh(Vector2<Double>(0, 0.7615941559557649)), Vector2(0, 1))
        expectClose(exp(Vector2<Double>(0, 1)), Vector2(1, 2.718281828459045))
        expectClose(exp2(Vector2<Double>(3, -1)), Vector2(8, 0.5))
        expectClose(log(Vector2<Double>(1, 2.718281828459045)), Vector2(0, 1))
        expectClose(log2(Vector2<Double>(8, 0.5)), Vector2(3, -1))
        expectClose(pow(Vector2<Double>(2, 9), Vector2(3, 0.5)), Vector2(8, 3))
    }

    @Test
    func applyToScalars() {
        #expect(sin(0.0) == 0)
        #expect(cos(0.0) == 1)
        #expect(abs(atan2(1.0, 0.0) - .pi / 2) < 1e-12)
        #expect(exp2(Float(3)) == 8)
        #expect(log2(8.0) == 3)
        #expect(pow(2.0, 10.0) == 1024)
        #expect(abs(log(exp(1.5)) - 1.5) < 1e-12)
    }

    @Test
    func takeFloatVectors() {
        let result = sin(Vector3<Float>(0, .pi / 2, .pi))
        #expect(all(abs(result - Vector3(0, 1, 0)) < Vector3(repeating: 1e-6)))
    }

    private func expectClose(
        _ actual: Vector2<Double>, _ expected: Vector2<Double>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            all(abs(actual - expected) < Vector2(repeating: 1e-12)),
            "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }
}
