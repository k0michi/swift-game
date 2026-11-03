import Dawn

/// A label on a rectangle that runs `action` when it is clicked.
struct Button: PrimitiveView {
    var label: any View
    var action: () -> Void

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Group) {
        self.label = label()
        self.action = action
    }

    init(_ title: String, action: @escaping () -> Void) {
        label = Text(title)
        self.action = action
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [ButtonNode(label: context.resolveOne(label), action: action, graph: context.graph)]
    }
}

struct ButtonNode: Node {
    var label: any Node
    var action: () -> Void
    let graph: ViewGraph

    private static let padding = (horizontal: Float(12), vertical: Float(6))

    func size(proposedWidth: Float?, in renderer: Compositor) -> (width: Float, height: Float) {
        let size = label.size(proposedWidth: proposedWidth.map { $0 - Self.padding.horizontal * 2 }, in: renderer)
        return (size.width + Self.padding.horizontal * 2, size.height + Self.padding.vertical * 2)
    }

    // Where it is drawn is where it is clicked, so its action runs as it is
    // drawn, and what it changes shows in the next frame.
    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: Compositor) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        if graph.clicks.contains(where: { (x..<x + size.width).contains($0.x) && (y..<y + size.height).contains($0.y) }) {
            action()
        }
        renderer.fill(x: x, y: y, width: size.width, height: size.height, color: Color(r: 0.2, g: 0.24, b: 0.32, a: 1))
        try label.draw(
            x: x + Self.padding.horizontal, y: y + Self.padding.vertical,
            proposedWidth: proposedWidth.map { $0 - Self.padding.horizontal * 2 }, in: renderer)
    }
}
