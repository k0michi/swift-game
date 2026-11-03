import SDL3

#if os(Emscripten)
    import CGameToolkitWeb
#endif

/// What text input brings in a frame.
public enum TextInputUpdate: Equatable, Sendable {
    /// The text an input method is composing, empty when it is done, with what
    /// it has selected in it, in the units the platform gives, if anything.
    case composition(String, selection: Range<Int>?)
    /// Text entered: typed, or what an input method composed.
    case commit(String)
}

/// Text input for a window, from its input methods, on the desktop and in the
/// browser alike. SDL brings it on the desktop. In the browser, whose SDL
/// brings no input methods' composition, an invisible input element of its
/// own does.
///
/// Its updates come out of the SDL events given to `handle(_:)`, in their
/// order: in the browser, the input element's come in user events of their
/// own. Keys that edit, such as Backspace, are still SDL's key events, but
/// for those an input method takes while it composes.
@MainActor
public final class TextInput {
    private let window: Window
    // In the browser, the event type of the input element's updates, which
    // their codes find.
    private let eventType: EventType?
    private var pending: [Int32: TextInputUpdate] = [:]
    private var nextCode: Int32 = 0
    public private(set) var isActive = false
    /// Whether an input method is composing, when keys are its own.
    public private(set) var isComposing = false

    public init(window: Window) {
        self.window = window
        #if os(Emscripten)
            eventType = registerEvents(numevents: 1)
        #else
            eventType = nil
        #endif
    }

    deinit {
        #if os(Emscripten)
            if isActive {
                game_toolkit_web_stop_text_input()
            }
        #endif
    }

    /// Starts taking text, and showing an input method's or the screen's
    /// keyboard where there is one.
    public func start() throws {
        // In the browser too, for SDL to leave typed keys to the input element.
        try startTextInput(window: window)
        #if os(Emscripten)
            game_toolkit_web_start_text_input(Unmanaged.passUnretained(self).toOpaque()) { context, kind, text in
                let input = Unmanaged<TextInput>.fromOpaque(context!).takeUnretainedValue()
                let string = String(cString: text!)
                game_toolkit_web_free(text)
                input.post(kind == 0 ? .composition(string, selection: nil) : .commit(string))
            }
        #endif
        isActive = true
    }

    public func stop() throws {
        #if os(Emscripten)
            game_toolkit_web_stop_text_input()
        #endif
        try stopTextInput(window: window)
        isActive = false
        isComposing = false
    }

    /// Where the text being entered is, in points from the window's top-left
    /// corner, and the cursor's offset in it, for an input method to show what
    /// it composes and its candidates beside it.
    public func setArea(x: Float, y: Float, width: Float, height: Float, cursor: Int32) throws {
        #if os(Emscripten)
            game_toolkit_web_set_text_input_area(Double(x), Double(y), Double(width), Double(height))
        #else
            try setTextInputArea(
                window: window,
                rect: Rect(x: Int32(x.rounded()), y: Int32(y.rounded()), w: Int32(width.rounded()), h: Int32(height.rounded())),
                cursor: cursor)
        #endif
    }

    /// What `event` brings, if it brings text input. In the browser, SDL's
    /// own text events, which it makes of typed keys, are left out, as the
    /// input element brings the same text.
    public func handle(_ event: any Event) -> TextInputUpdate? {
        guard isActive else { return nil }
        var update: TextInputUpdate?
        #if os(Emscripten)
            if let event = event as? UserEvent, event.type == eventType {
                update = pending.removeValue(forKey: event.code)
            }
        #else
            switch event {
            case let event as TextEditingEvent:
                let selection = event.start >= 0 ? Int(event.start)..<Int(event.start + max(event.length, 0)) : nil
                update = .composition(event.text, selection: selection)
            case let event as TextInputEvent:
                update = .commit(event.text)
            default:
                break
            }
        #endif
        if case .composition(let text, _) = update {
            isComposing = !text.isEmpty
        } else if update != nil {
            isComposing = false
        }
        return update
    }

    // An update from the input element, which comes after the SDL events
    // before it.
    private func post(_ update: TextInputUpdate) {
        guard isActive, let eventType else { return }
        let code = nextCode
        nextCode &+= 1
        pending[code] = update
        try? pushEvent(event: UserEvent(type: eventType, code: code))
    }
}
