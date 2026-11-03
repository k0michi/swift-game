#if !os(macOS)
    // Linux's and Windows' swiftc find their SDK themselves, Windows' from
    // SDKROOT.

    /// What swiftc needs to build Build.swift on the host.
    func hostSDKArguments() throws -> [String] {
        []
    }
#endif
