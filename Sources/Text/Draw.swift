import Dawn

/// A view that records an item of `Kind` for its rectangle, behind its
/// content and as big as it, or `width` by `height` points when it has none:
/// how a view draws with a kind of drawing of its own.
struct Draw<Kind: DrawingKind>: PrimitiveView {
    /// The item for the view's rectangle, in pixels.
    var item: (Rect) -> Kind.Item
    var content: any View
    var size: (width: Float, height: Float)?

    init(_ kind: Kind.Type, item: @escaping (Rect) -> Kind.Item, @ViewBuilder content: () -> Group) {
        self.item = item
        self.content = content()
    }

    init(_ kind: Kind.Type, width: Float, height: Float, item: @escaping (Rect) -> Kind.Item) {
        self.item = item
        content = Group([])
        size = (width, height)
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [DrawNode<Kind>(item: item, content: context.resolve([content]), size: size)]
    }
}

struct DrawNode<Kind: DrawingKind>: Node {
    var item: (Rect) -> Kind.Item
    var content: [any Node]
    var size: (width: Float, height: Float)?

    func size(proposedWidth: Float?, in renderer: Compositor) -> (width: Float, height: Float) {
        size ?? single(content).size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: Compositor) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        renderer.draw(Kind.self, item(Rect(x: x, y: y, width: size.width, height: size.height).scaled(by: renderer.scale)))
        if !content.isEmpty {
            try single(content).draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
        }
    }
}

/// Content made for whether the pointer is over it and whether it is
/// pressed, as they were in the last frame, which runs `action` when it is
/// clicked: what a control of one's own is made of.
struct Pressable: PrimitiveView {
    var action: () -> Void
    var content: (Interaction) -> Group

    init(action: @escaping () -> Void, @ViewBuilder content: @escaping (Interaction) -> Group) {
        self.action = action
        self.content = content
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        let interaction = context.graph.interaction(at: context.identity)
        return [
            InteractiveNode(
                content: context.appending("content").resolveOne(content(interaction)), identity: context.identity,
                graph: context.graph, action: action)
        ]
    }
}

// A node that takes the frame's pointer where it is drawn, so that what it
// does when it is clicked happens as it is drawn, and shows in the next
// frame, as does whether it is hovered or pressed.
struct InteractiveNode: Node {
    var content: any Node
    let identity: Identity
    let graph: ViewGraph
    var action: (() -> Void)?

    func size(proposedWidth: Float?, in renderer: Compositor) -> (width: Float, height: Float) {
        content.size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: Compositor) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        graph.interact(at: identity, x: x, y: y, width: size.width, height: size.height, action: action)
        try content.draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
    }
}
