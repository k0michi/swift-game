import Dawn

/// What a view's ancestors set for it and the views in it, as SwiftUI's
/// EnvironmentValues: what the default views draw with, and the styles that
/// views such as Button are drawn in.
@MainActor
struct EnvironmentValues {
    var foregroundColor = Color(r: 1, g: 1, b: 1, a: 1)
    var fontSize: Float = 17
    var buttonStyle: any ButtonStyle = DefaultButtonStyle()
}

/// A view in an environment changed by `transform`.
struct EnvironmentWriter: PrimitiveView {
    var content: any View
    var transform: (inout EnvironmentValues) -> Void

    func makeNodes(in context: ResolveContext) -> [any Node] {
        var context = context
        transform(&context.environment)
        return context.resolve([content])
    }
}

extension View {
    func environment<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> EnvironmentWriter {
        EnvironmentWriter(content: self) { $0[keyPath: keyPath] = value }
    }

    /// The color of the text and shapes in it, as theirs unless they have
    /// their own.
    func foregroundColor(_ color: Color) -> EnvironmentWriter {
        environment(\.foregroundColor, color)
    }

    /// The size of the text in it, as theirs unless they have their own.
    func font(size points: Float) -> EnvironmentWriter {
        environment(\.fontSize, points)
    }

    /// The style the buttons in it are drawn in.
    func buttonStyle(_ style: some ButtonStyle) -> EnvironmentWriter {
        environment(\.buttonStyle, style)
    }
}
