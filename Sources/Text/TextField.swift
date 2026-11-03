import Dawn
import GameToolkit
import SDL3
import TextEditing

/// One line of text to edit, which a click gives the focus. While it has the
/// focus, it takes keys and text, and shows what an input method composes at
/// the caret, underlined.
struct TextField: PrimitiveView {
    var placeholder: String
    var text: Binding<String>
    var width: Float = 240
    var points: Float = 17
    var onSubmit: () -> Void = {}

    init(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self.text = text
        self.onSubmit = onSubmit
    }

    func makeNodes(in graph: ViewGraph, at identity: Identity) -> [any Node] {
        [TextFieldNode(field: self, identity: identity, graph: graph, state: graph.state(at: identity, initial: State()))]
    }

    // What it keeps from frame to frame.
    struct State {
        var editing = TextEditing()
        var composition = ""
        // How far its text is scrolled left, in points, for the caret to show.
        var scroll: Float = 0
        // When it last changed, for the caret to show steadily after it.
        var changed: Double = 0
    }
}

struct TextFieldNode: Node {
    let field: TextField
    let identity: Identity
    let graph: ViewGraph
    let state: StateBox<TextField.State>

    private static let padding = (horizontal: Float(8), vertical: Float(6))

    func size(proposedWidth: Float?, in renderer: TextRenderer) -> (width: Float, height: Float) {
        let run = renderer.run(" ", points: field.points)
        return (
            proposedWidth.map { min($0, field.width) } ?? field.width,
            Float(run.ascender - run.descender) / renderer.scale + Self.padding.vertical * 2
        )
    }

    func draw(x: Float, y: Float, proposedWidth: Float?, in renderer: TextRenderer) throws {
        let size = size(proposedWidth: proposedWidth, in: renderer)
        let inner = (x: x + Self.padding.horizontal, width: size.width - Self.padding.horizontal * 2)
        var fieldState = state.value
        fieldState.editing.text = field.text.wrappedValue

        // A click on it gives it the focus, and puts the caret where it was.
        let click = graph.clicks.last { (x..<x + size.width).contains($0.x) && (y..<y + size.height).contains($0.y) }
        if click != nil {
            graph.claimFocus(identity)
        }
        let focused = graph.hasFocus(identity)
        if focused {
            edit(&fieldState)
        } else {
            fieldState.composition = ""
        }

        // The text, with what is being composed at the caret.
        let text = fieldState.editing.text
        let caret = fieldState.editing.head
        let before = String(text[..<fieldState.editing.index(caret)])
        let display = before + fieldState.composition + String(text[fieldState.editing.index(caret)...])
        let run = renderer.run(display, points: field.points)
        func offset(_ utf8Offset: Int) -> Float {
            let x = utf8Offset >= display.utf8.count
                ? run.width : run.clusters.last { $0.offset <= utf8Offset }?.x ?? 0
            return Float(x) / 64 / renderer.scale
        }

        if let click, fieldState.composition.isEmpty {
            // The boundary between Characters nearest it.
            let target = click.x - inner.x + fieldState.scroll
            let nearest = (0...text.count).min { a, b in
                abs(offset(text.prefix(a).utf8.count) - target) < abs(offset(text.prefix(b).utf8.count) - target)
            }!
            fieldState.editing.moveCaret(to: nearest)
            fieldState.changed = graph.time
        }

        // Scrolled for the caret to show, and no further than the text goes.
        let caretX = offset(before.utf8.count + fieldState.composition.utf8.count)
        let textWidth = Float(run.width) / 64 / renderer.scale
        if caretX - fieldState.scroll > inner.width {
            fieldState.scroll = caretX - inner.width
        } else if caretX < fieldState.scroll {
            fieldState.scroll = caretX
        }
        fieldState.scroll = max(0, min(fieldState.scroll, textWidth - inner.width))
        let textX = inner.x - fieldState.scroll
        let textY = y + Self.padding.vertical
        let lineHeight = Float(run.ascender - run.descender) / renderer.scale

        renderer.fill(x: x, y: y, width: size.width, height: size.height, color: Color(r: 0.12, g: 0.13, b: 0.18, a: 1))
        if focused {
            let accent = Color(r: 0.4, g: 0.6, b: 1, a: 1)
            renderer.fill(x: x, y: y + size.height - 2, width: size.width, height: 2, color: accent)
        }
        renderer.clip = (inner.x, y, inner.width, size.height)
        defer { renderer.clip = nil }

        let selection = fieldState.editing.selection
        if focused && !selection.isEmpty && fieldState.composition.isEmpty {
            let start = offset(text.prefix(selection.lowerBound).utf8.count)
            let end = offset(text.prefix(selection.upperBound).utf8.count)
            renderer.fill(
                x: textX + start, y: textY, width: end - start, height: lineHeight,
                color: Color(r: 0.25, g: 0.4, b: 0.7, a: 1))
        }
        if display.isEmpty {
            try renderer.draw(
                renderer.run(field.placeholder, points: field.points), x: inner.x, y: textY,
                color: Color(r: 0.5, g: 0.5, b: 0.55, a: 1))
        } else {
            try renderer.draw(run, x: textX, y: textY, color: Color(r: 1, g: 1, b: 1, a: 1))
        }
        if !fieldState.composition.isEmpty {
            let start = offset(before.utf8.count)
            renderer.fill(
                x: textX + start, y: textY + lineHeight - 1, width: caretX - start, height: 1,
                color: Color(r: 1, g: 1, b: 1, a: 1))
        }
        // The caret, which blinks but for a while after a change.
        if focused && (graph.time - fieldState.changed).truncatingRemainder(dividingBy: 1) < 0.5 {
            renderer.fill(
                x: textX + caretX, y: textY, width: 1.5, height: lineHeight, color: Color(r: 1, g: 1, b: 1, a: 1))
        }

        if focused {
            // Where an input method shows what it composes, and its candidates.
            try graph.textInput.setArea(
                x: x, y: y, width: size.width, height: size.height, cursor: Int32(textX + caretX - x))
        }
        state.value = fieldState
    }

    // What the frame's keys and text do to it.
    private func edit(_ fieldState: inout TextField.State) {
        let original = fieldState.editing
        for input in graph.inputs {
            switch input {
            case .text(.composition(let text, _)):
                fieldState.composition = text
                fieldState.changed = graph.time
            case .text(.commit(let text)):
                fieldState.editing.insert(text)
                fieldState.composition = ""
            case .key(let key) where fieldState.composition.isEmpty:
                let extending = !key.mod.isDisjoint(with: .shift)
                // Command on macOS, Control elsewhere.
                let command = !key.mod.isDisjoint(with: [.gui, .ctrl])
                switch key.key {
                case .backspace: fieldState.editing.deleteBackward()
                case .delete: fieldState.editing.deleteForward()
                case .left where command, .home: fieldState.editing.moveToStart(extending: extending)
                case .right where command, .end: fieldState.editing.moveToEnd(extending: extending)
                case .left: fieldState.editing.moveLeft(extending: extending)
                case .right: fieldState.editing.moveRight(extending: extending)
                case .a where command: fieldState.editing.selectAll()
                case .return, .kpEnter: field.onSubmit()
                default: break
                }
            case .key:
                // An input method's, while it composes.
                break
            }
        }
        if fieldState.editing != original {
            fieldState.changed = graph.time
            if fieldState.editing.text != field.text.wrappedValue {
                field.text.wrappedValue = fieldState.editing.text
            }
        }
    }
}
