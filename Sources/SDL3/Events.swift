import CSDL3

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

    public static let mouseMotion = Self(rawValue: 0x400)
    public static let mouseButtonDown = Self(rawValue: 0x401)
    public static let mouseButtonUp = Self(rawValue: 0x402)
    public static let mouseWheel = Self(rawValue: 0x403)

    public static let pollSentinel = Self(rawValue: 0x7F00)
    public static let user = Self(rawValue: 0x8000)
    public static let last = Self(rawValue: 0xFFFF)
}

public protocol Event: Sendable {
    var type: EventType { get }
    var timestamp: UInt64 { get }
}

public struct CommonEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
}

public struct WindowEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
    public let windowID: WindowID
    public let data1: Int32
    public let data2: Int32
}

public struct QuitEvent: Event {
    public let type: EventType
    public let timestamp: UInt64
}

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
    case EventType.quit.rawValue:
        return QuitEvent(type: type, timestamp: event.quit.timestamp)
    case EventType.terminating.rawValue ... EventType.systemThemeChanged.rawValue:
        return CommonEvent(type: type, timestamp: event.common.timestamp)
    default:
        return UnknownEvent(type: type, timestamp: event.common.timestamp)
    }
}

@MainActor
public func pumpEvents() {
    SDL_PumpEvents()
}

@MainActor
public func pollEvent() -> (any Event)? {
    var event = SDL_Event()
    return SDL_PollEvent(&event) ? makeEvent(from: event) : nil
}
