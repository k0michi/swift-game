import CSDL3

// SDL_EventType
public struct EventType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let first = Self(rawValue: 0)

    public static let quit = Self(rawValue: 0x100)
    public static let terminating = Self(rawValue: 0x101)
    public static let lowMemory = Self(rawValue: 0x102)
    public static let willEnterBackground = Self(rawValue: 0x103)
    public static let didEnterBackground = Self(rawValue: 0x104)
    public static let willEnterForeground = Self(rawValue: 0x105)
    public static let didEnterForeground = Self(rawValue: 0x106)
    public static let localeChanged = Self(rawValue: 0x107)
    public static let systemThemeChanged = Self(rawValue: 0x108)

    public static let windowShown = Self(rawValue: 0x202)
    public static let windowHidden = Self(rawValue: 0x203)
    public static let windowExposed = Self(rawValue: 0x204)
    public static let windowMoved = Self(rawValue: 0x205)
    public static let windowResized = Self(rawValue: 0x206)
    public static let windowPixelSizeChanged = Self(rawValue: 0x207)
    public static let windowMetalViewResized = Self(rawValue: 0x208)
    public static let windowMinimized = Self(rawValue: 0x209)
    public static let windowMaximized = Self(rawValue: 0x20A)
    public static let windowRestored = Self(rawValue: 0x20B)
    public static let windowMouseEnter = Self(rawValue: 0x20C)
    public static let windowMouseLeave = Self(rawValue: 0x20D)
    public static let windowFocusGained = Self(rawValue: 0x20E)
    public static let windowFocusLost = Self(rawValue: 0x20F)
    public static let windowCloseRequested = Self(rawValue: 0x210)
    public static let windowHitTest = Self(rawValue: 0x211)
    public static let windowICCProfileChanged = Self(rawValue: 0x212)
    public static let windowDisplayChanged = Self(rawValue: 0x213)
    public static let windowDisplayScaleChanged = Self(rawValue: 0x214)
    public static let windowSafeAreaChanged = Self(rawValue: 0x215)
    public static let windowOccluded = Self(rawValue: 0x216)
    public static let windowEnterFullscreen = Self(rawValue: 0x217)
    public static let windowLeaveFullscreen = Self(rawValue: 0x218)
    public static let windowDestroyed = Self(rawValue: 0x219)
    public static let windowHDRStateChanged = Self(rawValue: 0x21A)

    public static let keyDown = Self(rawValue: 0x300)
    public static let keyUp = Self(rawValue: 0x301)
    public static let textEditing = Self(rawValue: 0x302)
    public static let textInput = Self(rawValue: 0x303)
    public static let keymapChanged = Self(rawValue: 0x304)
    public static let keyboardAdded = Self(rawValue: 0x305)
    public static let keyboardRemoved = Self(rawValue: 0x306)

    public static let mouseMotion = Self(rawValue: 0x400)
    public static let mouseButtonDown = Self(rawValue: 0x401)
    public static let mouseButtonUp = Self(rawValue: 0x402)
    public static let mouseWheel = Self(rawValue: 0x403)
    public static let mouseAdded = Self(rawValue: 0x404)
    public static let mouseRemoved = Self(rawValue: 0x405)

    public static let pollSentinel = Self(rawValue: 0x7F00)
    public static let user = Self(rawValue: 0x8000)
    public static let last = Self(rawValue: 0xFFFF)
}

// SDL_Event
public protocol Event: Sendable {
    var type: EventType { get }
    var timestamp: UInt64 { get }
}

// SDL_CommonEvent
public struct CommonEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
}

// SDL_WindowEvent
public struct WindowEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let data1: Int32
    public let data2: Int32
}

// SDL_KeyboardEvent
public struct KeyboardEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let which: KeyboardID
    public let scancode: Scancode
    public let key: Keycode
    public let mod: Keymod
    public let raw: UInt16
    public let down: Bool
    public let `repeat`: Bool
}

// SDL_MouseMotionEvent
public struct MouseMotionEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let which: MouseID
    public let state: MouseButtonFlags
    public let x: Float
    public let y: Float
    public let xrel: Float
    public let yrel: Float
}

// SDL_MouseButtonEvent
public struct MouseButtonEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let which: MouseID
    public let button: UInt8
    public let down: Bool
    public let clicks: UInt8
    public let x: Float
    public let y: Float
}

// SDL_MouseWheelEvent
public struct MouseWheelEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let which: MouseID
    public let x: Float
    public let y: Float
    public let direction: MouseWheelDirection
    public let mouseX: Float
    public let mouseY: Float
    public let integerX: Int32
    public let integerY: Int32
}

// SDL_QuitEvent
public struct QuitEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
}

// SDL_Event
public struct UnknownEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
}

private func makeEvent(from event: SDL_Event) -> any Event {
    let type = EventType(rawValue: event.type)

    switch type.rawValue {
    case EventType.windowShown.rawValue ... EventType.windowHDRStateChanged.rawValue:
        return WindowEvent(
            type: type,
            timestamp: event.window.timestamp,
            windowID: WindowID(rawValue: event.window.windowID),
            data1: event.window.data1,
            data2: event.window.data2
        )
    case EventType.keyDown.rawValue, EventType.keyUp.rawValue:
        return KeyboardEvent(
            type: type,
            timestamp: event.key.timestamp,
            windowID: WindowID(rawValue: event.key.windowID),
            which: KeyboardID(rawValue: event.key.which),
            scancode: Scancode(rawValue: event.key.scancode.rawValue),
            key: Keycode(rawValue: event.key.key),
            mod: Keymod(rawValue: event.key.mod),
            raw: event.key.raw,
            down: event.key.down,
            repeat: event.key.repeat
        )
    case EventType.mouseMotion.rawValue:
        return MouseMotionEvent(
            type: type,
            timestamp: event.motion.timestamp,
            windowID: WindowID(rawValue: event.motion.windowID),
            which: MouseID(rawValue: event.motion.which),
            state: MouseButtonFlags(rawValue: event.motion.state),
            x: event.motion.x,
            y: event.motion.y,
            xrel: event.motion.xrel,
            yrel: event.motion.yrel
        )
    case EventType.mouseButtonDown.rawValue, EventType.mouseButtonUp.rawValue:
        return MouseButtonEvent(
            type: type,
            timestamp: event.button.timestamp,
            windowID: WindowID(rawValue: event.button.windowID),
            which: MouseID(rawValue: event.button.which),
            button: event.button.button,
            down: event.button.down,
            clicks: event.button.clicks,
            x: event.button.x,
            y: event.button.y
        )
    case EventType.mouseWheel.rawValue:
        return MouseWheelEvent(
            type: type,
            timestamp: event.wheel.timestamp,
            windowID: WindowID(rawValue: event.wheel.windowID),
            which: MouseID(rawValue: event.wheel.which),
            x: event.wheel.x,
            y: event.wheel.y,
            direction: MouseWheelDirection(rawValue: event.wheel.direction.rawValue),
            mouseX: event.wheel.mouse_x,
            mouseY: event.wheel.mouse_y,
            integerX: event.wheel.integer_x,
            integerY: event.wheel.integer_y
        )
    case EventType.quit.rawValue:
        return QuitEvent(type: type, timestamp: event.quit.timestamp)
    case EventType.terminating.rawValue ... EventType.systemThemeChanged.rawValue:
        return CommonEvent(type: type, timestamp: event.common.timestamp)
    default:
        return UnknownEvent(type: type, timestamp: event.common.timestamp)
    }
}

// SDL_PumpEvents
@MainActor
public func pumpEvents() {
    SDL_PumpEvents()
}

// SDL_PollEvent
@MainActor
public func pollEvent() -> (any Event)? {
    var event = SDL_Event()
    return SDL_PollEvent(&event) ? makeEvent(from: event) : nil
}
