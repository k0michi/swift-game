import Dawn

// An experiment in describing the screen the way SwiftUI does, rebuilt every
// frame from what it shows.
//
// A view is a value. Most are made of others, by their body, and may keep
// state between frames in @State. The primitive ones, at the bottom, resolve
// into nodes, which lay out and draw. Each frame, ViewGraph evaluates the
// bodies from the root down into a tree of nodes.

@MainActor
protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

// The body of the primitive views, which have none. The `return` keeps
// ViewBuilder from building it.
extension Never: View {
    var body: Never { return fatalError() }
}

/// A view that is not made of others, but resolves into nodes itself.
@MainActor
protocol PrimitiveView: View where Body == Never {
    func makeNodes(in context: ResolveContext) -> [any Node]
}

extension PrimitiveView {
    var body: Never { return fatalError("\(Self.self) has no body") }
}

/// Where a view is resolved: its graph, its identity, and its environment.
@MainActor
struct ResolveContext {
    let graph: ViewGraph
    var identity: Identity
    var environment: EnvironmentValues

    /// The context of a view under this one's, by `component`.
    func appending(_ component: AnyHashable) -> ResolveContext {
        var context = self
        context.identity = identity.appending(component)
        return context
    }

    /// The nodes of `views`, each at its place under this view.
    func resolve(_ views: [any View]) -> [any Node] {
        graph.resolve(views, in: self)
    }

    /// The nodes of `view`, as one.
    func resolveOne(_ view: any View) -> any Node {
        single(resolve([view]))
    }
}

/// What a view resolves into, which lays out and draws in points. Its parent
/// proposes the width it may take, or nil for as wide as it likes, and it
/// answers how big it is in that width, and draws itself in it, which text
/// needs to know where its lines break.
@MainActor
protocol Node {
    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float)
    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws
}

// The views in a builder's block, each in a place of its own. An `if` takes
// one place, empty when its condition is false, and an `if`-`else` one, with
// which branch it took, so that the views after them keep their places, and
// each branch its own identity.
@MainActor
@resultBuilder
enum ViewBuilder {
    static func buildExpression(_ view: any View) -> [any View] { [view] }
    static func buildBlock(_ views: [any View]...) -> [any View] { views.flatMap { $0 } }
    // A container's content, or a body, which is one view.
    static func buildFinalResult(_ views: [any View]) -> [any View] { views }
    static func buildFinalResult(_ views: [any View]) -> Group { Group(views) }
    static func buildOptional(_ views: [any View]?) -> [any View] { [Group(views ?? [])] }
    static func buildEither(first views: [any View]) -> [any View] { [Group(views).id(0)] }
    static func buildEither(second views: [any View]) -> [any View] { [Group(views).id(1)] }
    static func buildArray(_ views: [[any View]]) -> [any View] { views.map { Group($0) } }
}

/// Views laid out by the view that holds them as if they were its own.
struct Group: PrimitiveView {
    var content: [any View]

    init(_ content: [any View]) {
        self.content = content
    }

    init(@ViewBuilder content: () -> [any View]) {
        self.content = content()
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        context.resolve(content)
    }
}

/// A view with an identity of its own, rather than its place.
struct IdentifiedView: PrimitiveView {
    var content: any View
    var id: AnyHashable

    func makeNodes(in context: ResolveContext) -> [any Node] {
        context.appending(id).resolve([content])
    }
}

extension View {
    func id(_ id: some Hashable) -> IdentifiedView {
        IdentifiedView(content: self, id: AnyHashable(id))
    }
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
// and as high as its first line's ascender to its last one's descender. Its
// size and color are the environment's unless it is given its own.
struct Text: PrimitiveView {
    var string: String
    var points: Float?
    var color: Color?
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

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [
            TextNode(
                string: string, points: points ?? context.environment.fontSize,
                color: color ?? context.environment.foregroundColor, alignment: alignment)
        ]
    }
}

struct TextNode: Node {
    var string: String
    var points: Float
    var color: Color
    var alignment: HorizontalAlignment

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
struct VStack: PrimitiveView {
    var alignment: HorizontalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: HorizontalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [VStackNode(alignment: alignment, spacing: spacing, content: context.resolve(content))]
    }
}

struct VStackNode: Node {
    var alignment: HorizontalAlignment
    var spacing: Float
    var content: [any Node]

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
        for node in content {
            let size = node.size(proposedWidth: proposedWidth, in: renderer)
            try node.draw(
                x: x + alignment.offset(of: size.width, in: width), y: y, proposedWidth: proposedWidth, in: renderer)
            y += size.height + spacing
        }
    }
}

// Views side by side, `spacing` points apart, each as wide as it likes.
struct HStack: PrimitiveView {
    var alignment: VerticalAlignment
    var spacing: Float
    var content: [any View]

    init(alignment: VerticalAlignment = .center, spacing: Float = 8, @ViewBuilder content: () -> [any View]) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [HStackNode(alignment: alignment, spacing: spacing, content: context.resolve(content))]
    }
}

struct HStackNode: Node {
    var alignment: VerticalAlignment
    var spacing: Float
    var content: [any Node]

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
        for node in content {
            let size = node.size(proposedWidth: nil, in: renderer)
            let offset: Float =
                switch alignment {
                case .top: 0
                case .center: (height - size.height) / 2
                case .bottom: height - size.height
                }
            try node.draw(x: x, y: y + offset, proposedWidth: nil, in: renderer)
            x += size.width + spacing
        }
    }
}

// The nodes a modifier's content resolves into, as one: a vertical stack of
// them when there are more.
@MainActor
func single(_ nodes: [any Node]) -> any Node {
    nodes.count == 1 ? nodes[0] : VStackNode(alignment: .leading, spacing: 0, content: nodes)
}

// A view with space around it, proposed what is left of the width.
struct Padding: PrimitiveView {
    var content: any View
    var horizontal: Float
    var vertical: Float

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [PaddingNode(content: context.resolveOne(content), horizontal: horizontal, vertical: vertical)]
    }
}

struct PaddingNode: Node {
    var content: any Node
    var horizontal: Float
    var vertical: Float

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let size = content.size(proposedWidth: proposedWidth.map { $0 - horizontal * 2 }, in: renderer)
        return (size.width + horizontal * 2, size.height + vertical * 2)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        try content.draw(
            x: x + horizontal, y: y + vertical, proposedWidth: proposedWidth.map { $0 - horizontal * 2 }, in: renderer)
    }
}

// A view proposed `width` points, whatever its parent proposes, and that
// wide, with the view placed in it by `alignment`.
struct Frame: PrimitiveView {
    var content: any View
    var width: Float
    var alignment: HorizontalAlignment

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [FrameNode(content: context.resolveOne(content), width: width, alignment: alignment)]
    }
}

struct FrameNode: Node {
    var content: any Node
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

// A view over a rectangle of `color` as big as it is.
struct Background: PrimitiveView {
    var content: any View
    var color: Color

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [BackgroundNode(content: context.resolveOne(content), color: color)]
    }
}

struct BackgroundNode: Node {
    var content: any Node
    var color: Color

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        content.size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let size = content.size(proposedWidth: proposedWidth, in: renderer)
        renderer.fill(x: x, y: y, width: size.width, height: size.height, color: color)
        try content.draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
    }
}

extension View {
    func padding(_ amount: Float = 16) -> Padding {
        Padding(content: self, horizontal: amount, vertical: amount)
    }

    func padding(horizontal: Float = 0, vertical: Float = 0) -> Padding {
        Padding(content: self, horizontal: horizontal, vertical: vertical)
    }

    func frame(width: Float, alignment: HorizontalAlignment = .center) -> Frame {
        Frame(content: self, width: width, alignment: alignment)
    }

    func background(_ color: Color) -> Background {
        Background(content: self, color: color)
    }
}
