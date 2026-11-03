import Dawn

/// Drawing of one's own with WebGPU, for GPUView: made once for a view, with
/// the device and the format it draws into, and kept as long as the view is,
/// so that it can make its pipelines and buffers once. Each frame, it records
/// its drawing of the view's parameters into the frame's render pass, over
/// what is drawn before the view and under what is drawn after it.
@MainActor
protocol GPUDrawing: AnyObject {
    associatedtype Parameters

    init(device: Device, format: TextureFormat) throws

    func draw(_ parameters: Parameters, in context: GPUDrawContext) throws
}

/// Where a GPUDrawing draws: the frame's render pass, and the view's
/// rectangle and the screen, in pixels, from its top-left corner.
struct GPUDrawContext {
    let device: Device
    let pass: RenderPassEncoder
    let x: Float
    let y: Float
    let width: Float
    let height: Float
    let screenWidth: Float
    let screenHeight: Float
    /// Pixels to the point.
    let scale: Float
    /// When the frame is, in seconds.
    let time: Double
}

/// A view that `Drawing` draws itself, behind its content and as big as it,
/// or `width` by `height` points when it has none.
struct GPUView<Drawing: GPUDrawing>: PrimitiveView {
    var parameters: Drawing.Parameters
    var content: any View
    var size: (width: Float, height: Float)?

    init(_ drawing: Drawing.Type, parameters: Drawing.Parameters, @ViewBuilder content: () -> Group) {
        self.parameters = parameters
        self.content = content()
    }

    init(_ drawing: Drawing.Type, parameters: Drawing.Parameters, width: Float, height: Float) {
        self.parameters = parameters
        content = Group([])
        size = (width, height)
    }

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [
            GPUNode<Drawing>(
                content: context.resolve([content]), size: size, parameters: parameters, graph: context.graph,
                drawing: context.graph.state(at: context.identity, initial: nil))
        ]
    }
}

struct GPUNode<Drawing: GPUDrawing>: Node {
    var content: [any Node]
    var size: (width: Float, height: Float)?
    var parameters: Drawing.Parameters
    let graph: ViewGraph
    let drawing: StateBox<Drawing?>

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        size ?? single(content).size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let drawing = try drawing.value ?? Drawing(device: renderer.device, format: renderer.format)
        self.drawing.value = drawing
        let size = size(proposedWidth: proposedWidth, in: renderer)
        let (parameters, scale, time) = (parameters, renderer.scale, graph.time)
        let device = renderer.device
        renderer.drawCustom { pass, screenWidth, screenHeight in
            try drawing.draw(
                parameters,
                in: GPUDrawContext(
                    device: device, pass: pass, x: x * scale, y: y * scale, width: size.width * scale,
                    height: size.height * scale, screenWidth: screenWidth, screenHeight: screenHeight, scale: scale,
                    time: time))
        }
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

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        content.size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        graph.interact(at: identity, x: x, y: y, width: size.width, height: size.height, action: action)
        try content.draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
    }
}
