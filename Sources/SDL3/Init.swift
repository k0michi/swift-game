import CSDL3

// SDL_InitFlags
public struct InitFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let audio = Self(rawValue: SDL_INIT_AUDIO)
    public static let video = Self(rawValue: SDL_INIT_VIDEO)
    public static let joystick = Self(rawValue: SDL_INIT_JOYSTICK)
    public static let haptic = Self(rawValue: SDL_INIT_HAPTIC)
    public static let gamepad = Self(rawValue: SDL_INIT_GAMEPAD)
    public static let events = Self(rawValue: SDL_INIT_EVENTS)
    public static let sensor = Self(rawValue: SDL_INIT_SENSOR)
    public static let camera = Self(rawValue: SDL_INIT_CAMERA)
}

// SDL_Quit
@MainActor
public final class System {
    private static var activeSystems: [WeakSystem] = []
    private static var initializationCount = 0
    private let flags: InitFlags

    static func active(for flags: InitFlags) -> System? {
        activeSystems.reversed().lazy.compactMap(\.value).first {
            $0.flags.contains(flags)
        }
    }

    fileprivate init(flags: InitFlags) {
        self.flags = flags
        Self.initializationCount += 1
        Self.activeSystems.removeAll { $0.value == nil }
        Self.activeSystems.append(WeakSystem(self))
    }

    isolated deinit {
        SDL_QuitSubSystem(flags.rawValue)
        Self.initializationCount -= 1
        Self.activeSystems.removeAll { $0.value == nil || $0.value === self }
        Self.quitIfUnused()
    }

    fileprivate static func quitIfUnused() {
        if initializationCount == 0 { SDL_Quit() }
    }
}

@MainActor
private final class WeakSystem {
    weak var value: System?

    init(_ value: System) {
        self.value = value
    }
}

// SDL_Init
@MainActor
public func `init`(flags: InitFlags) throws -> System {
    guard SDL_Init(flags.rawValue) else {
        let error = SDLError(operation: "SDL_Init")
        System.quitIfUnused()
        throw error
    }

    return System(flags: flags)
}

// SDL_QuitSubSystem
public typealias Subsystem = System

// SDL_InitSubSystem
@MainActor
public func initSubsystem(flags: InitFlags) throws -> Subsystem {
    guard SDL_InitSubSystem(flags.rawValue) else {
        let error = SDLError(operation: "SDL_InitSubSystem")
        System.quitIfUnused()
        throw error
    }

    return System(flags: flags)
}

// SDL_WasInit
@MainActor
public func wasInit(flags: InitFlags) -> InitFlags {
    InitFlags(rawValue: SDL_WasInit(flags.rawValue))
}
