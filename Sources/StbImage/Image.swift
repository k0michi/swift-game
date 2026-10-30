import CStbImage

// Copies what stb_image returns and frees it, or throws why it returned
// nothing.
private func takeImage<Element>(
    _ operation: String,
    desiredChannels: Int32,
    _ load: (_ x: inout Int32, _ y: inout Int32, _ channelsInFile: inout Int32) -> UnsafeMutablePointer<Element>?
) throws -> (data: [Element], x: Int32, y: Int32, channelsInFile: Int32) {
    var x: Int32 = 0
    var y: Int32 = 0
    var channelsInFile: Int32 = 0
    guard let pixels = load(&x, &y, &channelsInFile) else {
        throw StbImageError(operation: operation)
    }
    defer { stbi_image_free(pixels) }
    let channels = desiredChannels == 0 ? channelsInFile : desiredChannels
    let data = Array(UnsafeBufferPointer(start: pixels, count: Int(x) * Int(y) * Int(channels)))
    return (data, x, y, channelsInFile)
}

// stbi_load_from_memory
public func loadFromMemory(
    buffer: [UInt8], desiredChannels: Int32 = 0
) throws -> (data: [UInt8], x: Int32, y: Int32, channelsInFile: Int32) {
    try takeImage("stbi_load_from_memory", desiredChannels: desiredChannels) { x, y, channelsInFile in
        stbi_load_from_memory(buffer, Int32(buffer.count), &x, &y, &channelsInFile, desiredChannels)
    }
}

// stbi_load
public func load(
    filename: String, desiredChannels: Int32 = 0
) throws -> (data: [UInt8], x: Int32, y: Int32, channelsInFile: Int32) {
    try takeImage("stbi_load", desiredChannels: desiredChannels) { x, y, channelsInFile in
        stbi_load(filename, &x, &y, &channelsInFile, desiredChannels)
    }
}

// stbi_load_16_from_memory
public func load16FromMemory(
    buffer: [UInt8], desiredChannels: Int32 = 0
) throws -> (data: [UInt16], x: Int32, y: Int32, channelsInFile: Int32) {
    try takeImage("stbi_load_16_from_memory", desiredChannels: desiredChannels) { x, y, channelsInFile in
        stbi_load_16_from_memory(buffer, Int32(buffer.count), &x, &y, &channelsInFile, desiredChannels)
    }
}

// stbi_loadf_from_memory
public func loadfFromMemory(
    buffer: [UInt8], desiredChannels: Int32 = 0
) throws -> (data: [Float], x: Int32, y: Int32, channelsInFile: Int32) {
    try takeImage("stbi_loadf_from_memory", desiredChannels: desiredChannels) { x, y, channelsInFile in
        stbi_loadf_from_memory(buffer, Int32(buffer.count), &x, &y, &channelsInFile, desiredChannels)
    }
}

// stbi_info_from_memory
public func infoFromMemory(buffer: [UInt8]) throws -> (x: Int32, y: Int32, comp: Int32) {
    var x: Int32 = 0
    var y: Int32 = 0
    var comp: Int32 = 0
    guard stbi_info_from_memory(buffer, Int32(buffer.count), &x, &y, &comp) != 0 else {
        throw StbImageError(operation: "stbi_info_from_memory")
    }
    return (x, y, comp)
}

// stbi_info
public func info(filename: String) throws -> (x: Int32, y: Int32, comp: Int32) {
    var x: Int32 = 0
    var y: Int32 = 0
    var comp: Int32 = 0
    guard stbi_info(filename, &x, &y, &comp) != 0 else {
        throw StbImageError(operation: "stbi_info")
    }
    return (x, y, comp)
}

// stbi_is_16_bit_from_memory
public func is16BitFromMemory(buffer: [UInt8]) -> Bool {
    stbi_is_16_bit_from_memory(buffer, Int32(buffer.count)) != 0
}

// stbi_is_hdr_from_memory
public func isHdrFromMemory(buffer: [UInt8]) -> Bool {
    stbi_is_hdr_from_memory(buffer, Int32(buffer.count)) != 0
}

// stbi_set_flip_vertically_on_load
public func setFlipVerticallyOnLoad(_ flagTrueIfShouldFlip: Bool) {
    stbi_set_flip_vertically_on_load(flagTrueIfShouldFlip ? 1 : 0)
}

// stbi_set_flip_vertically_on_load_thread
public func setFlipVerticallyOnLoadThread(_ flagTrueIfShouldFlip: Bool) {
    stbi_set_flip_vertically_on_load_thread(flagTrueIfShouldFlip ? 1 : 0)
}
