#if os(macOS)
    import Foundation

    // macOS's swiftc, outside Xcode's and SwiftPM's, needs the SDK to find
    // Foundation in, unless SDKROOT names it.

    /// What swiftc needs to build Build.swift on the host.
    func hostSDKArguments() throws -> [String] {
        if ProcessInfo.processInfo.environment["SDKROOT"] != nil {
            return []
        }
        let sdk = try output(of: ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["-sdk", sdk]
    }
#endif
