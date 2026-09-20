@testable import Echo
import Testing

@Test(arguments: [
    (source: [Float](arrayLiteral: 2), destinationCount: 2, expected: [2, 2]),
    (source: [Float](arrayLiteral: 2), destinationCount: 4, expected: [2, 2, 0, 0]),
    (source: [Float](arrayLiteral: 2), destinationCount: 6, expected: [0, 0, 2, 0, 0, 0]),
    (source: [1, 2], destinationCount: 4, expected: [1, 2, 0, 0]),
    (source: [1, 2], destinationCount: 6, expected: [1, 2, 0, 0, 0, 0]),
    (source: [1, 2, 3, 4], destinationCount: 6, expected: [1, 2, 0, 0, 3, 4]),
])
func speakerUpMixing(
    source: [Float],
    destinationCount: Int,
    expected: [Float]
) {
    #expect(mixOneFrame(source, to: destinationCount, interpretation: .speakers) == expected)
}

@Test func speakerDownMixing() {
    let squareRootOfOneHalf = Float(0.5).squareRoot()

    #expect(mixOneFrame([2, 4], to: 1, interpretation: .speakers) == [3])
    #expect(mixOneFrame([1, 2, 3, 4], to: 1, interpretation: .speakers) == [2.5])
    expectApproximatelyEqual(
        mixOneFrame([1, 2, 3, 100, 4, 5], to: 1, interpretation: .speakers),
        [squareRootOfOneHalf * 3 + 3 + 4.5]
    )
    #expect(mixOneFrame([1, 2, 3, 4], to: 2, interpretation: .speakers) == [2, 3])
    expectApproximatelyEqual(
        mixOneFrame([1, 2, 3, 100, 4, 5], to: 2, interpretation: .speakers),
        [1 + squareRootOfOneHalf * 7, 2 + squareRootOfOneHalf * 8]
    )
    expectApproximatelyEqual(
        mixOneFrame([1, 2, 3, 100, 4, 5], to: 4, interpretation: .speakers),
        [1 + squareRootOfOneHalf * 3, 2 + squareRootOfOneHalf * 3, 4, 5]
    )
}

@Test func discreteMixingMatchesChannelsByIndex() {
    #expect(mixOneFrame([1, 2], to: 4, interpretation: .discrete) == [1, 2, 0, 0])
    #expect(mixOneFrame([1, 2, 3, 4], to: 2, interpretation: .discrete) == [1, 2])
}

private func mixOneFrame(
    _ samples: [Float],
    to destinationCount: Int,
    interpretation: ChannelInterpretation
) -> [Float] {
    let source = AudioRenderQuantum(channelCapacity: samples.count, frameCount: 1)
    for (channel, sample) in samples.enumerated() {
        source.channelData(channel)[0] = sample
    }

    let destination = AudioRenderQuantum(channelCapacity: destinationCount, frameCount: 1)
    ChannelMixer.mix(source, into: destination, interpretation: interpretation)
    return (0 ..< destinationCount).map { destination.channelData($0)[0] }
}

private func expectApproximatelyEqual(_ actual: [Float], _ expected: [Float]) {
    #expect(actual.count == expected.count)
    for (actual, expected) in zip(actual, expected) {
        #expect(abs(actual - expected) < 0.000_001)
    }
}
