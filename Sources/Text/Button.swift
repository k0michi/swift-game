import Dawn

/// How a button looks, as SwiftUI's ButtonStyle: a view made of its label,
/// for whether it is pressed or the pointer is over it. `buttonStyle(_:)`
/// sets it for the buttons in a view, and DefaultButtonStyle is the one they
/// have otherwise.
@MainActor
protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration

    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// What a button style makes a button of.
struct ButtonStyleConfiguration {
    /// The button's label.
    var label: any View
    var isPressed: Bool
    var isHovered: Bool
}

/// The look a button has unless it is given another: its label on a
/// rectangle, lighter when the pointer is over it and darker when it is
/// pressed.
struct DefaultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shade: Double = configuration.isPressed ? 0.14 : configuration.isHovered ? 0.3 : 0.22
        configuration.label
            .padding(horizontal: 12, vertical: 6)
            .background(Color(r: shade, g: shade + 0.04, b: shade + 0.12, a: 1))
    }
}

/// A label that runs `action` when it is clicked, in the environment's
/// button style.
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
        let interaction = context.graph.interaction(at: context.identity)
        let configuration = ButtonStyleConfiguration(
            label: label, isPressed: interaction.isPressed, isHovered: interaction.isHovered)
        let body = makeBody(of: context.environment.buttonStyle, configuration: configuration)
        return [
            InteractiveNode(
                content: context.appending("style").resolveOne(body), identity: context.identity,
                graph: context.graph, action: action)
        ]
    }

    private func makeBody(of style: some ButtonStyle, configuration: ButtonStyleConfiguration) -> any View {
        style.makeBody(configuration: configuration)
    }
}

/// A view that runs `action` when it is clicked, as SwiftUI's onTapGesture.
struct TapGesture: PrimitiveView {
    var content: any View
    var action: () -> Void

    func makeNodes(in context: ResolveContext) -> [any Node] {
        [
            InteractiveNode(
                content: context.resolveOne(content), identity: context.identity, graph: context.graph,
                action: action)
        ]
    }
}

extension View {
    func onTapGesture(perform action: @escaping () -> Void) -> TapGesture {
        TapGesture(content: self, action: action)
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

    var fills: Bool { content.fills }

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        content.size(proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        graph.interact(at: identity, x: x, y: y, width: size.width, height: size.height, action: action)
        try content.draw(x: x, y: y, proposedWidth: proposedWidth, in: renderer)
    }

    func draw(x: Float, y: Float, width: Float, height: Float, in renderer: TextRenderer) throws {
        graph.interact(at: identity, x: x, y: y, width: width, height: height, action: action)
        try content.draw(x: x, y: y, width: width, height: height, in: renderer)
    }
}
