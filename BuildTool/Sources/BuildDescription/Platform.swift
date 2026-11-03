import Foundation

/// What the project is built for.
public enum Platform: String, Codable, Sendable, CaseIterable {
    case macOS, linux, windows, emscripten

    /// The platform BuildTool runs on.
    public static var host: Platform {
        #if os(macOS)
            .macOS
        #elseif os(Windows)
            .windows
        #else
            .linux
        #endif
    }
}

/// The platform Build.swift describes the build for, which buildtool's
/// `--platform` chooses, so that it declares what differs between platforms
/// with plain `if`s.
public let platform: Platform =
    ProcessInfo.processInfo.environment[Build.platformVariable].flatMap(Platform.init(rawValue:)) ?? .host
