import Foundation
import Testing
import VectorMath

@Suite("Matrix")
struct MatrixTests {
    @Test
    func layoutIsPackedColumns() {
        #expect(MemoryLayout<Matrix2x2<Float>>.size == 16)
        #expect(MemoryLayout<Matrix3x3<Float>>.size == 36)
        #expect(MemoryLayout<Matrix4x4<Float>>.size == 64)
        #expect(MemoryLayout<Matrix2x3<Float>>.stride == 24)
        #expect(MemoryLayout<Matrix4x3<Double>>.stride == 96)
        #expect(MemoryLayout<Matrix2x3<Float>>.offset(of: \.columns.1) == 12)

        let matrix = Matrix2x3<Float>(1, 2, 3, 4, 5, 6)
        let scalars = withUnsafeBytes(of: matrix) { Array($0.bindMemory(to: Float.self)) }
        #expect(scalars == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func initializersAreColumnMajor() {
        let byColumns = Matrix3x2(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6))
        #expect(Matrix3x2(1, 2, 3, 4, 5, 6) == byColumns)
        #expect(Matrix3x2(columns: (Vector2(1, 2), Vector2(3, 4), Vector2(5, 6))) == byColumns)
        #expect(Matrix3x2(rows: (Vector3(1, 3, 5), Vector3(2, 4, 6))) == byColumns)
        #expect(byColumns[1] == Vector2(3, 4))
        #expect(byColumns[2, 0] == 5)
        #expect(Matrix3x2<Int>.columnCount == 3 && Matrix3x2<Int>.rowCount == 2)
    }

    @Test
    func subscriptsWriteColumnsAndElements() {
        var matrix = Matrix2x2<Int>.zero
        matrix[1] = Vector2(3, 4)
        matrix[0, 1] = 2
        #expect(matrix == Matrix2x2(0, 2, 3, 4))
    }

    @Test
    func identityHasOnesOnTheDiagonal() {
        #expect(Matrix3x3<Int>.identity == Matrix3x3(1, 0, 0, 0, 1, 0, 0, 0, 1))
        let vector = Vector4<Float>(1, 2, 3, 4)
        #expect(Matrix4x4<Float>.identity * vector == vector)
    }

    @Test
    func arithmeticIsElementwise() {
        let a = Matrix2x2(1, 2, 3, 4)
        let b = Matrix2x2(5, 6, 7, 8)
        #expect(a + b == Matrix2x2(6, 8, 10, 12))
        #expect(b - a == Matrix2x2(4, 4, 4, 4))
        #expect(-a == Matrix2x2(-1, -2, -3, -4))
        #expect(a * 2 == Matrix2x2(2, 4, 6, 8))
        #expect(2 * a == Matrix2x2(2, 4, 6, 8))
    }

    @Test
    func productsMatchTheDefinition() {
        // A 3x2 times a 4x3 is a 4x2: each element is a row of the left times
        // a column of the right.
        let lhs = Matrix3x2(1, 2, 3, 4, 5, 6)
        let rhs = Matrix4x3(1, 0, 2, -1, 3, 1, 0, 2, 2, 4, -2, 0)
        let product = lhs * rhs
        for column in 0..<4 {
            for row in 0..<2 {
                var expected = 0
                for k in 0..<3 {
                    expected += lhs[k, row] * rhs[column, k]
                }
                #expect(product[column, row] == expected)
            }
        }

        // Matrix times column vector, and row vector times matrix.
        #expect(lhs * Vector3(1, 1, 1) == Vector2(9, 12))
        #expect(Vector2(1, 1) * lhs == Vector3(3, 7, 11))

        var square = Matrix2x2(1, 2, 3, 4)
        square *= Matrix2x2<Int>.identity
        #expect(square == Matrix2x2(1, 2, 3, 4))
    }

    @Test
    func transposeSwapsRowsAndColumns() {
        let matrix = Matrix3x2(1, 2, 3, 4, 5, 6)
        let transposed = transpose(matrix)
        #expect(transposed == Matrix2x3(1, 3, 5, 2, 4, 6))
        #expect(transpose(transposed) == matrix)
    }

    @Test
    func determinants() {
        #expect(determinant(Matrix2x2(1, 2, 3, 4)) == -2)
        #expect(determinant(Matrix3x3(2, 0, 0, 0, 3, 0, 0, 0, 4)) == 24)
        #expect(determinant(Matrix3x3(1, 2, 3, 4, 5, 6, 7, 8, 10)) == -3)
        #expect(determinant(Matrix4x4(1, 0, 2, -1, 3, 0, 0, 5, 2, 1, 4, -3, 1, 0, 5, 0)) == 30)
        #expect(determinant(Matrix4x4<Int>.identity) == 1)
    }

    @Test
    func inverseUndoesTheMatrix() {
        let m2 = Matrix2x2<Double>(4, 7, 2, 6)
        expectClose(inverse(m2) * m2, .identity)

        let m3 = Matrix3x3<Double>(1, 2, 3, 0, 1, 4, 5, 6, 0)
        expectClose(inverse(m3) * m3, .identity)
        expectClose(m3 * inverse(m3), .identity)

        let m4 = Matrix4x4<Double>(1, 0, 2, -1, 3, 0, 0, 5, 2, 1, 4, -3, 1, 0, 5, 0)
        expectClose(inverse(m4) * m4, .identity)
        expectClose(m4 * inverse(m4), .identity)
    }

    @Test
    func conversionsChangeTheScalarType() {
        #expect(Matrix2x2<Float>(Matrix2x2<Int>(1, 2, 3, 4)) == Matrix2x2(1, 2, 3, 4))
        #expect(Matrix2x2<Int>(Matrix2x2<Double>(1.5, 2, 3, -4.5)) == Matrix2x2(1, 2, 3, -4))
    }

    @Test
    func codableAsNestedArrays() throws {
        let matrix = Matrix2x3(1, 2, 3, 4, 5, 6)
        let data = try JSONEncoder().encode(matrix)
        #expect(String(decoding: data, as: UTF8.self) == "[[1,2,3],[4,5,6]]")
        #expect(try JSONDecoder().decode(Matrix2x3<Int>.self, from: data) == matrix)
    }

    @Test
    func descriptionListsColumns() {
        #expect(Matrix2x2(1, 2, 3, 4).description == "Matrix2x2(Vector2(1, 2), Vector2(3, 4))")
    }
}

private let tolerance = 1e-9

private func expectClose(
    _ actual: Matrix2x2<Double>, _ expected: Matrix2x2<Double>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for column in 0..<2 {
        let close = abs(actual[column] - expected[column]) < Vector2(repeating: tolerance)
        #expect(all(close), "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }
}

private func expectClose(
    _ actual: Matrix3x3<Double>, _ expected: Matrix3x3<Double>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for column in 0..<3 {
        let close = abs(actual[column] - expected[column]) < Vector3(repeating: tolerance)
        #expect(all(close), "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }
}

private func expectClose(
    _ actual: Matrix4x4<Double>, _ expected: Matrix4x4<Double>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for column in 0..<4 {
        let close = abs(actual[column] - expected[column]) < Vector4(repeating: tolerance)
        #expect(all(close), "\(actual) is not close to \(expected)", sourceLocation: sourceLocation)
    }
}
