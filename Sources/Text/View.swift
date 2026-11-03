import Dawn

// Something to lay out and draw, in points: an experiment in describing the
// screen the way SwiftUI does, rebuilt every frame from what it shows.
//
// A view's parent proposes the width it may take, or nil for as wide as it
// likes, and the view answers how big it is in that width, and draws itself
// in it, which text needs to know where its lines break.
@MainActor
protocol View {
    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float)
    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws
}

@resultBuilder
enum ViewBuilder {
    static func buildExpression(_ view: any View) -> [any View] { [view] }
    static func buildBlock(_ views: [any View]...) -> [any View] { views.flatMap { $0 } }
    static func buildOptional(_ views: [any View]?) -> [any View] { views ?? [] }
    static func buildEither(first views: [any View]) -> [any View] { views }
    static func buildEither(second views: [any View]) -> [any View] { views }
    static func buildArray(_ views: [[any View]]) -> [any View] { views.flatMap { $0 } }
}

enum HorizontalAlignment {
    case leading, center, trailing

    // How far in a view `width` wide sits in `space`.
    func offset(of width: Float, in space: Float) -> Float {
        switch self {
        case .leading: 0
        case .center: (space - width) / 2
        case .trailing: space - width
        }
    }
}

enum VerticalAlignment {
    case top, center, bottom
}

// Lines of text, broken where they are too wide for the width proposed, and
// at newlines, the font's line height apart. It is as wide as its widest line,
// and as high as its first line's ascender to its last one's descender.
struct Text: View {
    var string: String
    var points: Float = 17
    var color = Color(r: 1, g: 1, b: 1, a: 1)
    var alignment = HorizontalAlignment.leading

    init(_ string: String) {
        self.string = string
    }

    func font(size points: Float) -> Text {
        var text = self
        text.points = points
        return text
    }

    func foregroundColor(_ color: Color) -> Text {
        var text = self
        text.color = color
        return text
    }

    // How its lines line up with one another.
    func multilineTextAlignment(_ alignment: HorizontalAlignment) -> Text {
        var text = self
        text.alignment = alignment
        return text
    }

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let lines = renderer.lines(string, points: points, width: proposedWidth)
        let first = lines.first!
        let height = first.ascender - first.descender + first.lineHeight * (lines.count - 1)
        return (Float(lines.map(\.width).max()!) / 64 / renderer.scale, Float(height) / renderer.scale)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let lines = renderer.lines(string, points: points, width: proposedWidth)
        let width = Float(lines.map(\.width).max()!) / 64 / renderer.scale
        var y = y
        for line in lines {
            let lineWidth = Float(line.width) / 64 / renderer.scale
            try renderer.draw(line, x: x + alignment.offset(of: lineWidth, in: width), y: y, color: color)
            y += Float(line.lineHeight) / renderer.scale
        }
    }
}

// Views one below another, `spacing` points apart, each proposed the width
// the stack is.
struct VStack: View {
    var alignment: HorizontalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: HorizontalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let sizes = content.map { $0.size(proposedWidth: proposedWidth, in: renderer) }
        return (
            sizes.map(\.width).max() ?? 0,
            sizes.map(\.height).reduce(0, +) + spacing * Float(max(sizes.count - 1, 0))
        )
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let width = size(proposedWidth: proposedWidth, in: renderer).width
        var y = y
        for view in content {
            let size = view.size(proposedWidth: proposedWidth, in: renderer)
            try view.draw(
                x: x + alignment.offset(of: size.width, in: width), y: y, proposedWidth: proposedWidth, in: renderer)
            y += size.height + spacing
        }
    }
}

// Views side by side, `spacing` points apart, each as wide as it likes.
struct HStack: View {
    var alignment: VerticalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: VerticalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let sizes = content.map { $0.size(proposedWidth: nil, in: renderer) }
        return (
            sizes.map(\.width).reduce(0, +) + spacing * Float(max(sizes.count - 1, 0)),
            sizes.map(\.height).max() ?? 0
        )
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let height = size(proposedWidth: proposedWidth, in: renderer).height
        var x = x
        for view in content {
            let size = view.size(proposedWidth: nil, in: renderer)
            let offset: Float =
                switch alignment {
                case .top: 0
                case .center: (height - size.height) / 2
                case .bottom: height - size.height
                }
            try view.draw(x: x, y: y + offset, proposedWidth: nil, in: renderer)
            x += size.width + spacing
        }
    }
}

// A view with `amount` points around it, proposed what is left of the width.
struct Padding: View {
    var content: any View
    var amount: Float

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let size = content.size(proposedWidth: proposedWidth.map { $0 - amount * 2 }, in: renderer)
        return (size.width + amount * 2, size.height + amount * 2)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        try content.draw(
            x: x + amount, y: y + amount, proposedWidth: proposedWidth.map { $0 - amount * 2 }, in: renderer)
    }
}

// A view proposed `width` points, whatever its parent proposes, and that
// wide, with the view placed in it by `alignment`.
struct Frame: View {
    var content: any View
    var width: Float
    var alignment: HorizontalAlignment

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        (width, content.size(proposedWidth: width, in: renderer).height)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let size = content.size(proposedWidth: width, in: renderer)
        try content.draw(
            x: x + alignment.offset(of: size.width, in: width), y: y, proposedWidth: width, in: renderer)
    }
}

extension View {
    func padding(_ amount: Float = 16) -> Padding {
        Padding(content: self, amount: amount)
    }

    func frame(width: Float, alignment: HorizontalAlignment = .center) -> Frame {
        Frame(content: self, width: width, alignment: alignment)
    }
}
