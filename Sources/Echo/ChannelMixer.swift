enum ChannelMixer {
    private static let squareRootOfOneHalf = Float(0.5).squareRoot()

    static func mix(
        _ source: AudioRenderQuantum,
        into destination: AudioRenderQuantum,
        interpretation: ChannelInterpretation
    ) {
        precondition(source.frameCount == destination.frameCount)

        switch interpretation {
        case .discrete:
            mixDiscrete(source, into: destination)
        case .speakers:
            mixSpeakers(source, into: destination)
        }
    }

    private static func mixDiscrete(
        _ source: AudioRenderQuantum,
        into destination: AudioRenderQuantum
    ) {
        for channel in 0 ..< min(source.channelCount, destination.channelCount) {
            add(source.channelData(channel), to: destination.channelData(channel))
        }
    }

    private static func mixSpeakers(
        _ source: AudioRenderQuantum,
        into destination: AudioRenderQuantum
    ) {
        switch (source.channelCount, destination.channelCount) {
        case let (sourceCount, destinationCount) where sourceCount == destinationCount:
            mixDiscrete(source, into: destination)
        case (1, 2), (1, 4):
            add(source.channelData(0), to: destination.channelData(0))
            add(source.channelData(0), to: destination.channelData(1))
        case (1, 6):
            add(source.channelData(0), to: destination.channelData(2))
        case (2, 4), (2, 6):
            add(source.channelData(0), to: destination.channelData(0))
            add(source.channelData(1), to: destination.channelData(1))
        case (4, 6):
            add(source.channelData(0), to: destination.channelData(0))
            add(source.channelData(1), to: destination.channelData(1))
            add(source.channelData(2), to: destination.channelData(4))
            add(source.channelData(3), to: destination.channelData(5))
        case (2, 1):
            addPair(
                source.channelData(0),
                source.channelData(1),
                scale: 0.5,
                to: destination.channelData(0)
            )
        case (4, 1):
            for channel in 0 ..< 4 {
                add(source.channelData(channel), scale: 0.25, to: destination.channelData(0))
            }
        case (6, 1):
            add(source.channelData(0), scale: squareRootOfOneHalf, to: destination.channelData(0))
            add(source.channelData(1), scale: squareRootOfOneHalf, to: destination.channelData(0))
            add(source.channelData(2), to: destination.channelData(0))
            add(source.channelData(4), scale: 0.5, to: destination.channelData(0))
            add(source.channelData(5), scale: 0.5, to: destination.channelData(0))
        case (4, 2):
            addPair(
                source.channelData(0),
                source.channelData(2),
                scale: 0.5,
                to: destination.channelData(0)
            )
            addPair(
                source.channelData(1),
                source.channelData(3),
                scale: 0.5,
                to: destination.channelData(1)
            )
        case (6, 2):
            add(source.channelData(0), to: destination.channelData(0))
            add(source.channelData(1), to: destination.channelData(1))
            add(source.channelData(2), scale: squareRootOfOneHalf, to: destination.channelData(0))
            add(source.channelData(2), scale: squareRootOfOneHalf, to: destination.channelData(1))
            add(source.channelData(4), scale: squareRootOfOneHalf, to: destination.channelData(0))
            add(source.channelData(5), scale: squareRootOfOneHalf, to: destination.channelData(1))
        case (6, 4):
            add(source.channelData(0), to: destination.channelData(0))
            add(source.channelData(1), to: destination.channelData(1))
            add(source.channelData(2), scale: squareRootOfOneHalf, to: destination.channelData(0))
            add(source.channelData(2), scale: squareRootOfOneHalf, to: destination.channelData(1))
            add(source.channelData(4), to: destination.channelData(2))
            add(source.channelData(5), to: destination.channelData(3))
        default:
            mixDiscrete(source, into: destination)
        }
    }

    private static func add(
        _ source: UnsafeMutableBufferPointer<Float>,
        scale: Float = 1,
        to destination: UnsafeMutableBufferPointer<Float>
    ) {
        for frame in source.indices {
            destination[frame] += source[frame] * scale
        }
    }

    private static func addPair(
        _ first: UnsafeMutableBufferPointer<Float>,
        _ second: UnsafeMutableBufferPointer<Float>,
        scale: Float,
        to destination: UnsafeMutableBufferPointer<Float>
    ) {
        for frame in first.indices {
            destination[frame] += scale * (first[frame] + second[frame])
        }
    }
}
