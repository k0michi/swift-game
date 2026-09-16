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
    static weak var active: System?

    fileprivate init() {}

    isolated deinit {
        SDL_Quit()
    }
}

// SDL_Init
@MainActor
public func `init`(flags: InitFlags) throws -> System {
    guard System.active == nil else {
        throw SDLError(
            operation: "SDL_Init",
            message: "an SDL system is already active"
        )
    }

    guard SDL_Init(flags.rawValue) else {
        throw SDLError(operation: "SDL_Init")
    }

    let system = System()
    System.active = system
    return system
}

// SDL_QuitSubSystem
@MainActor
public final class Subsystem {
    private let flags: InitFlags
    private let system: System

    fileprivate init(flags: InitFlags, system: System) {
        self.flags = flags
        self.system = system
    }

    isolated deinit {
        SDL_QuitSubSystem(flags.rawValue)
    }
}

// SDL_InitSubSystem
@MainActor
public func initSubsystem(flags: InitFlags) throws -> Subsystem {
    guard let system = System.active else {
        throw SDLError(
            operation: "SDL_InitSubSystem",
            message: "SDL is not initialized"
        )
    }

    guard SDL_InitSubSystem(flags.rawValue) else {
        throw SDLError(operation: "SDL_InitSubSystem")
    }

    return Subsystem(flags: flags, system: system)
}

// SDL_WasInit
@MainActor
public func wasInit(flags: InitFlags) -> InitFlags {
    InitFlags(rawValue: SDL_WasInit(flags.rawValue))
}
