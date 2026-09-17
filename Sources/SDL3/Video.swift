import CSDL3

// SDL_WindowID
public struct WindowID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct WindowPixelSize: Equatable, Hashable, Sendable {
    public var w: Int32
    public var h: Int32

    public init(w: Int32, h: Int32) {
        self.w = w
        self.h = h
    }
}

// SDL_WindowFlags
public struct WindowFlags: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let fullscreen = Self(rawValue: CSDL3_WINDOW_FULLSCREEN)
    public static let openGL = Self(rawValue: CSDL3_WINDOW_OPENGL)
    public static let occluded = Self(rawValue: CSDL3_WINDOW_OCCLUDED)
    public static let hidden = Self(rawValue: CSDL3_WINDOW_HIDDEN)
    public static let borderless = Self(rawValue: CSDL3_WINDOW_BORDERLESS)
    public static let resizable = Self(rawValue: CSDL3_WINDOW_RESIZABLE)
    public static let minimized = Self(rawValue: CSDL3_WINDOW_MINIMIZED)
    public static let maximized = Self(rawValue: CSDL3_WINDOW_MAXIMIZED)
    public static let mouseGrabbed = Self(rawValue: CSDL3_WINDOW_MOUSE_GRABBED)
    public static let inputFocus = Self(rawValue: CSDL3_WINDOW_INPUT_FOCUS)
    public static let mouseFocus = Self(rawValue: CSDL3_WINDOW_MOUSE_FOCUS)
    public static let external = Self(rawValue: CSDL3_WINDOW_EXTERNAL)
    public static let modal = Self(rawValue: CSDL3_WINDOW_MODAL)
    public static let highPixelDensity = Self(rawValue: CSDL3_WINDOW_HIGH_PIXEL_DENSITY)
    public static let mouseCapture = Self(rawValue: CSDL3_WINDOW_MOUSE_CAPTURE)
    public static let mouseRelativeMode = Self(rawValue: CSDL3_WINDOW_MOUSE_RELATIVE_MODE)
    public static let alwaysOnTop = Self(rawValue: CSDL3_WINDOW_ALWAYS_ON_TOP)
    public static let utility = Self(rawValue: CSDL3_WINDOW_UTILITY)
    public static let tooltip = Self(rawValue: CSDL3_WINDOW_TOOLTIP)
    public static let popupMenu = Self(rawValue: CSDL3_WINDOW_POPUP_MENU)
    public static let keyboardGrabbed = Self(rawValue: CSDL3_WINDOW_KEYBOARD_GRABBED)
    public static let fillDocument = Self(rawValue: CSDL3_WINDOW_FILL_DOCUMENT)
    public static let vulkan = Self(rawValue: CSDL3_WINDOW_VULKAN)
    public static let metal = Self(rawValue: CSDL3_WINDOW_METAL)
    public static let transparent = Self(rawValue: CSDL3_WINDOW_TRANSPARENT)
    public static let notFocusable = Self(rawValue: CSDL3_WINDOW_NOT_FOCUSABLE)
}

// SDL_PROP_WINDOW_WIN32_HWND_POINTER
public let propWindowWin32HWNDPointer = "SDL.window.win32.hwnd"

// SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER
public let propWindowWin32InstancePointer = "SDL.window.win32.instance"

// SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER
public let propWindowWaylandDisplayPointer = "SDL.window.wayland.display"

// SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER
public let propWindowWaylandSurfacePointer = "SDL.window.wayland.surface"

// SDL_PROP_WINDOW_X11_DISPLAY_POINTER
public let propWindowX11DisplayPointer = "SDL.window.x11.display"

// SDL_PROP_WINDOW_X11_WINDOW_NUMBER
public let propWindowX11WindowNumber = "SDL.window.x11.window"

// SDL_Window
@MainActor
public final class Window {
    private let system: System
    private let pointer: OpaquePointer

    var cPointer: OpaquePointer {
        pointer
    }

    fileprivate init(system: System, pointer: OpaquePointer) {
        self.system = system
        self.pointer = pointer
    }

    isolated deinit {
        SDL_DestroyWindow(pointer)
    }
}

// SDL_CreateWindow
@MainActor
public func createWindow(
    title: String,
    w: Int32,
    h: Int32,
    flags: WindowFlags
) throws -> Window {
    guard let system = System.active else {
        throw SDLError(
            operation: "SDL_CreateWindow",
            message: "SDL is not initialized"
        )
    }

    guard let pointer = SDL_CreateWindow(title, w, h, flags.rawValue) else {
        throw SDLError(operation: "SDL_CreateWindow")
    }

    return Window(system: system, pointer: pointer)
}

// SDL_GetWindowProperties
@MainActor
public func getWindowProperties(window: Window) throws -> PropertiesID {
    let rawValue = SDL_GetWindowProperties(window.cPointer)
    guard rawValue != 0 else {
        throw SDLError(operation: "SDL_GetWindowProperties")
    }
    return PropertiesID(rawValue: rawValue)
}

// SDL_GetWindowSizeInPixels
@MainActor
public func getWindowSizeInPixels(window: Window) throws -> WindowPixelSize {
    var w: Int32 = 0
    var h: Int32 = 0
    guard SDL_GetWindowSizeInPixels(window.cPointer, &w, &h) else {
        throw SDLError(operation: "SDL_GetWindowSizeInPixels")
    }
    return WindowPixelSize(w: w, h: h)
}
