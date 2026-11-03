import Dawn

// Something to lay out and draw, in points: an experiment in describing the
// screen the way SwiftUI does, rebuilt every frame from what it shows.
@MainActor
protocol View {
    func size(in renderer: TextRenderer) -> (width: Float, height: Float)
    func draw(x: Float, y: Float, in renderer: TextRenderer) throws
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

// One line, as high as the font's ascender to descender.
struct Text: View {
    var string: String
    var points: Float = 17
    var color = Color(r: 1, g: 1, b: 1, a: 1)

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

    func size(in renderer: TextRenderer) -> (width: Float, height: Float) {
        let run = renderer.run(string, points: points)
        return (Float(run.width) / 64 / renderer.scale, Float(run.ascender - run.descender) / renderer.scale)
    }

    func draw(x: Float, y: Float, in renderer: TextRenderer) throws {
        try renderer.draw(renderer.run(string, points: points), x: x, y: y, color: color)
    }
}

enum HorizontalAlignment {
    case leading, center, trailing
}

enum VerticalAlignment {
    case top, center, bottom
}

// Views one below another, `spacing` points apart.
struct VStack: View {
    var alignment: HorizontalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: HorizontalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func size(in renderer: TextRenderer) -> (width: Float, height: Float) {
        let sizes = content.map { $0.size(in: renderer) }
        return (
            sizes.map(\.width).max() ?? 0,
            sizes.map(\.height).reduce(0, +) + spacing * Float(max(sizes.count - 1, 0))
        )
    }

    func draw(x: Float, y: Float, in renderer: TextRenderer) throws {
        let width = size(in: renderer).width
        var y = y
        for view in content {
            let size = view.size(in: renderer)
            let offset: Float =
                switch alignment {
                case .leading: 0
                case .center: (width - size.width) / 2
                case .trailing: width - size.width
                }
            try view.draw(x: x + offset, y: y, in: renderer)
            y += size.height + spacing
        }
    }
}

// Views side by side, `spacing` points apart.
struct HStack: View {
    var alignment: VerticalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: VerticalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func size(in renderer: TextRenderer) -> (width: Float, height: Float) {
        let sizes = content.map { $0.size(in: renderer) }
        return (
            sizes.map(\.width).reduce(0, +) + spacing * Float(max(sizes.count - 1, 0)),
            sizes.map(\.height).max() ?? 0
        )
    }

    func draw(x: Float, y: Float, in renderer: TextRenderer) throws {
        let height = size(in: renderer).height
        var x = x
        for view in content {
            let size = view.size(in: renderer)
            let offset: Float =
                switch alignment {
                case .top: 0
                case .center: (height - size.height) / 2
                case .bottom: height - size.height
                }
            try view.draw(x: x, y: y + offset, in: renderer)
            x += size.width + spacing
        }
    }
}

// A view with `amount` points around it.
struct Padding: View {
    var content: any View
    var amount: Float

    func size(in renderer: TextRenderer) -> (width: Float, height: Float) {
        let size = content.size(in: renderer)
        return (size.width + amount * 2, size.height + amount * 2)
    }

    func draw(x: Float, y: Float, in renderer: TextRenderer) throws {
        try content.draw(x: x + amount, y: y + amount, in: renderer)
    }
}

extension View {
    func padding(_ amount: Float = 16) -> Padding {
        Padding(content: self, amount: amount)
    }
}
