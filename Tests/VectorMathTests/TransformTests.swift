import Testing
import VectorMath

@Suite("Transforms")
struct TransformTests {
    @Test
    func translationAndScaleMovePoints() {
        let point = Vector4<Float>(1, 2, 3, 1)
        #expect(Matrix4x4.translation(Vector3(10, 20, 30)) * point == Vector4(11, 22, 33, 1))
        #expect(Matrix4x4.scale(Vector3(2, 3, 4)) * point == Vector4(2, 6, 12, 1))
        // Directions, with w = 0, do not move.
        #expect(Matrix4x4.translation(Vector3(10, 20, 30)) * Vector4(1, 0, 0, 0) == Vector4(1, 0, 0, 0))
    }

    @Test
    func rotationIsCounterclockwiseAroundTheAxis() {
        let quarter = Double.pi / 2
        expectClose(Matrix4x4.rotation(angle: quarter, axis: Vector3(0, 0, 1)) * Vector4(1, 0, 0, 1), Vector4(0, 1, 0, 1))
        expectClose(Matrix4x4.rotation(angle: quarter, axis: Vector3(1, 0, 0)) * Vector4(0, 1, 0, 1), Vector4(0, 0, 1, 1))
        expectClose(Matrix4x4.rotation(angle: quarter, axis: Vector3(0, 5, 0)) * Vector4(0, 0, 1, 1), Vector4(1, 0, 0, 1))
    }

    @Test
    func orthographicMapsTheBoxOntoClipSpace() {
        for (handedness, forward) in [(Handedness.right, -1.0), (.left, 1.0)] {
            let projection = Matrix4x4<Double>.orthographic(
                left: -2, right: 6, bottom: -1, top: 3, near: 1, far: 11,
                handedness: handedness, depth: .zeroToOne)
            expectClose(projection * Vector4(-2, -1, forward * 1, 1), Vector4(-1, -1, 0, 1))
            expectClose(projection * Vector4(6, 3, forward * 11, 1), Vector4(1, 1, 1, 1))
        }
        // Window coordinates, y down.
        let window = Matrix4x4<Double>.orthographic(
            left: 0, right: 800, bottom: 480, top: 0, near: -1, far: 1,
            handedness: .right, depth: .zeroToOne)
        expectClose(window * Vector4(0, 0, 0, 1), Vector4(-1, 1, 0.5, 1))
        expectClose(window * Vector4(800, 480, 0, 1), Vector4(1, -1, 0.5, 1))
    }

    @Test
    func perspectiveMapsNearAndFarToTheClipDepths() {
        let cases: [(ClipDepth, Double, Double)] = [
            (.zeroToOne, 0, 1), (.oneToZero, 1, 0), (.negativeOneToOne, -1, 1),
        ]
        for (depth, nearDepth, farDepth) in cases {
            for (handedness, forward) in [(Handedness.right, -1.0), (.left, 1.0)] {
                let projection = Matrix4x4<Double>.perspective(
                    fovY: .pi / 2, aspectRatio: 2, near: 1, far: 100,
                    handedness: handedness, depth: depth)
                // The top right corner of the near plane, and the center of the far one.
                expectClose(projected(projection, Vector3(2, 1, forward)), Vector3(1, 1, nearDepth))
                expectClose(projected(projection, Vector3(0, 0, forward * 100)), Vector3(0, 0, farDepth))
            }
        }
    }

    @Test
    func perspectiveWithAnInfiniteFarPlane() {
        let projection = Matrix4x4<Double>.perspective(
            fovY: .pi / 2, aspectRatio: 1, near: 1, far: .infinity, handedness: .right, depth: .oneToZero)
        expectClose(projected(projection, Vector3(0, 0, -1)), Vector3(0, 0, 1))
        #expect(projected(projection, Vector3(0, 0, -1e12)).z < 1e-11)
    }

    @Test
    func frustumMatchesGLFrustum() {
        // glFrustum(-1, 3, -2, 2, 1, 10), right-handed, depths from -1 to 1.
        let projection = Matrix4x4<Double>.frustum(
            left: -1, right: 3, bottom: -2, top: 2, near: 1, far: 10,
            handedness: .right, depth: .negativeOneToOne)
        let expected = Matrix4x4<Double>(
            rows: (
                Vector4(0.5, 0, 0.5, 0),
                Vector4(0, 0.5, 0, 0),
                Vector4(0, 0, -11.0 / 9, -20.0 / 9),
                Vector4(0, 0, -1, 0)
            ))
        for column in 0..<4 {
            expectClose(projection[column], expected[column])
        }
    }

    @Test
    func lookAtPutsTheTargetInFront() {
        let eye = Vector3<Double>(1, 2, 3)
        let target = Vector3<Double>(1, 2, -7)
        let right = Matrix4x4.lookAt(eye: eye, target: target, up: Vector3(0, 1, 0), handedness: .right)
        expectClose(right * Vector4(target, 1), Vector4(0, 0, -10, 1))
        expectClose(right * Vector4(eye + Vector3(1, 0, 0), 1), Vector4(1, 0, 0, 1))
        expectClose(right * Vector4(eye + Vector3(0, 1, 0), 1), Vector4(0, 1, 0, 1))

        let left = Matrix4x4.lookAt(eye: eye, target: target, up: Vector3(0, 1, 0), handedness: .left)
        expectClose(left * Vector4(target, 1), Vector4(0, 0, 10, 1))
        // Looking toward -z, x right in view space is -x in world space.
        expectClose(left * Vector4(eye + Vector3(-1, 0, 0), 1), Vector4(1, 0, 0, 1))
    }

    @Test
    func twoDimensionalTransforms() {
        let point = Vector3<Double>(1, 0, 1)
        expectClose(Matrix3x3.translation(Vector2(2, 3)) * point, Vector3(3, 3, 1))
        expectClose(Matrix3x3.scale(Vector2(2, 3)) * Vector3(1, 1, 1), Vector3(2, 3, 1))
        expectClose(Matrix3x3.rotation(angle: .pi / 2) * point, Vector3(0, 1, 1))
    }

    private func projected(_ projection: Matrix4x4<Double>, _ point: Vector3<Double>) -> Vector3<Double> {
        let clip = projection * Vector4(point, 1)
        return clip.xyz / clip.w
    }

    private func expectClose(
        _ actual: Vector3<Double>, _ expected: Vector3<Double>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            all(abs(actual - expected) < Vector3(repeating: 1e-9)),
            "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }

    private func expectClose(
        _ actual: Vector4<Double>, _ expected: Vector4<Double>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            all(abs(actual - expected) < Vector4(repeating: 1e-9)),
            "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }
}
