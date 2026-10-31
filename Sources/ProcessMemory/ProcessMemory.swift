import CProcessMemory

/// The bytes of memory the process has in RAM now: its resident set, or its
/// working set on Windows. In a browser, where a page's memory cannot be
/// asked for, the size of the wasm memory, which only grows. Nil if the
/// platform cannot tell.
public func currentMemory() -> UInt64? {
    let bytes = process_memory_current()
    return bytes == 0 ? nil : bytes
}

/// The most the process has had in RAM, as `currentMemory` counts.
public func peakMemory() -> UInt64? {
    let bytes = process_memory_peak()
    return bytes == 0 ? nil : bytes
}
