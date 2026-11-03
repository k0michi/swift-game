import Dawn

/// A buffer of uniforms in slots 256 bytes apart, for a kind that draws each
/// item with uniforms of its own: each item's are written into a slot of the
/// frame, and bound at its offset. The slots are used again from the start
/// each frame.
@MainActor
final class UniformSlots {
    static let stride: UInt64 = 256

    let buffer: Dawn.Buffer
    private let capacity: Int
    private var next = 0

    init(device: Device, label: String, capacity: Int = 256) throws {
        self.capacity = capacity
        buffer = try device.createBuffer(
            descriptor: BufferDescriptor(label: label, usage: [.uniform, .copyDst], size: Self.stride * UInt64(capacity)))
    }

    func reset() {
        next = 0
    }

    /// Writes `values` into the next slot, and returns its offset.
    func write(_ values: [Float], queue: Queue) -> UInt32 {
        precondition(next < capacity, "More than \(capacity) uniforms in a frame")
        let offset = UInt64(next) * Self.stride
        next += 1
        values.withUnsafeBytes { queue.writeBuffer(buffer, bufferOffset: offset, data: $0) }
        return UInt32(offset)
    }
}
