@testable import Echo
import Testing

@Test func renderQuantumOwnsIndependentContiguousChannels() {
    let quantum = AudioRenderQuantum(channelCapacity: 2, frameCount: 3)

    quantum.channelData(0)[2] = 1
    quantum.channelData(1)[0] = 2

    #expect(Array(quantum.channelData(0)) == [0, 0, 1])
    #expect(Array(quantum.channelData(1)) == [2, 0, 0])
}

@Test func renderQuantumCanClearAndReuseItsStorage() {
    let quantum = AudioRenderQuantum(channelCapacity: 1, frameCount: 2)
    quantum.channelData(0).update(repeating: 1)

    quantum.clear()

    #expect(Array(quantum.channelData(0)) == [0, 0])
}

@Test func renderQuantumCopiesAndSumsWithoutReplacingStorage() {
    let source = AudioRenderQuantum(channelCapacity: 1, frameCount: 3)
    source.channelData(0)[0] = 0.25
    source.channelData(0)[1] = 0.5
    source.channelData(0)[2] = 1

    let destination = AudioRenderQuantum(channelCapacity: 1, frameCount: 3)
    let address = destination.channelData(0).baseAddress
    destination.copy(from: source)
    destination.sum(from: source)

    #expect(destination.channelData(0).baseAddress == address)
    #expect(Array(destination.channelData(0)) == [0.5, 1, 2])
}

@Test func renderQuantumCanChangeItsActiveChannelCountWithinCapacity() {
    let quantum = AudioRenderQuantum(channelCapacity: 2, frameCount: 1, channelCount: 0)

    quantum.setChannelCount(2)

    #expect(quantum.channelCount == 2)
    #expect(Array(quantum.channelData(0)) == [0])
    #expect(Array(quantum.channelData(1)) == [0])
}
