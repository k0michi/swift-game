import Dawn

/// A shape, which fills the rectangle it is given: with the environment's
/// foreground color, unless `fill` or `stroke` gives it a color of its own.
@MainActor
protocol Shape: PrimitiveView {
    /// The radius of its corners in a rectangle `width` by `height`.
    func cornerRadius(width: Float, height: Float) -> Float
}

extension Shape {
    func makeNodes(in context: ResolveContext) -> [any Node] {
        [ShapeNode(shape: self, color: context.environment.foregroundColor, lineWidth: nil)]
    }

    func fill(_ color: Color) -> FilledShape {
        FilledShape(shape: self, color: color, lineWidth: nil)
    }

    /// Its outline, `lineWidth` points wide, inside it.
    func stroke(_ color: Color, lineWidth: Float = 1) -> FilledShape {
        FilledShape(shape: self, color: color, lineWidth: lineWidth)
    }
}

struct Rectangle: Shape {
    func cornerRadius(width: Float, height: Float) -> Float { 0 }
}

struct RoundedRectangle: Shape {
    var cornerRadius: Float

    func cornerRadius(width: Float, height: Float) -> Float { cornerRadius }
}

/// A rectangle with its ends round.
struct Capsule: Shape {
    func cornerRadius(width: Float, height: Float) -> Float { min(width, height) / 2 }
}

struct FilledShape: PrimitiveView {
    var shape: any Shape
    var color: Color
    var lineWidth: Float?

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [ShapeNode(shape: shape, color: color, lineWidth: lineWidth)]
    }
}

struct ShapeNode: Node {
    var shape: any Shape
    var color: Color
    var lineWidth: Float?

    var fills: Bool { true }

    // Nothing, but what it is given to fill.
    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        (proposedWidth ?? 0, 0)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {}

    func draw(x: Float, y: Float, width: Float, height: Float, in renderer: TextRenderer) throws {
        let radius = shape.cornerRadius(width: width, height: height)
        if let lineWidth {
            renderer.stroke(
                x: x, y: y, width: width, height: height, color: color, lineWidth: lineWidth, cornerRadius: radius)
        } else {
            renderer.fill(x: x, y: y, width: width, height: height, color: color, cornerRadius: radius)
        }
    }
}
