import Foundation

enum AudioBusMixer {
    static func downMixToMono(_ source: AudioBus, frame: Int) -> Float {
        switch source.numberOfChannels {
        case 1:
            return source[0, frame]
        case 2:
            return 0.5 * (source[0, frame] + source[1, frame])
        case 4:
            return 0.25 * (
                source[0, frame] + source[1, frame] + source[2, frame] + source[3, frame]
            )
        case 6:
            return sqrt(0.5) * (source[0, frame] + source[1, frame])
                + source[2, frame]
                + 0.5 * (source[4, frame] + source[5, frame])
        default:
            return source[0, frame]
        }
    }

    static func mix(
        _ source: AudioBus,
        into destination: inout AudioBus,
        interpretation: ChannelInterpretation,
        frameCount: Int
    ) {
        guard interpretation == .speakers,
              [1, 2, 4, 6].contains(source.numberOfChannels),
              [1, 2, 4, 6].contains(destination.numberOfChannels)
        else {
            mixDiscrete(source, into: &destination, frameCount: frameCount)
            return
        }
        for frame in 0..<frameCount {
            mixSpeakers(source, into: &destination, frame: frame)
        }
    }

    private static func mixDiscrete(
        _ source: AudioBus,
        into destination: inout AudioBus,
        frameCount: Int
    ) {
        for channel in 0..<min(source.numberOfChannels, destination.numberOfChannels) {
            for frame in 0..<frameCount {
                destination[channel, frame] += source[channel, frame]
            }
        }
    }

    private static func mixSpeakers(
        _ source: AudioBus,
        into destination: inout AudioBus,
        frame: Int
    ) {
        switch (source.numberOfChannels, destination.numberOfChannels) {
        case let (sourceCount, destinationCount) where sourceCount == destinationCount:
            for channel in 0..<sourceCount {
                destination[channel, frame] += source[channel, frame]
            }
        case (1, 2), (1, 4):
            destination[0, frame] += source[0, frame]
            destination[1, frame] += source[0, frame]
        case (1, 6):
            destination[2, frame] += source[0, frame]
        case (2, 4), (2, 6):
            destination[0, frame] += source[0, frame]
            destination[1, frame] += source[1, frame]
        case (4, 6):
            destination[0, frame] += source[0, frame]
            destination[1, frame] += source[1, frame]
            destination[4, frame] += source[2, frame]
            destination[5, frame] += source[3, frame]
        case (2, 1):
            destination[0, frame] += 0.5 * (source[0, frame] + source[1, frame])
        case (4, 1):
            destination[0, frame] += 0.25 * (
                source[0, frame] + source[1, frame] + source[2, frame] + source[3, frame]
            )
        case (6, 1):
            destination[0, frame] += sqrt(0.5) * (source[0, frame] + source[1, frame])
                + source[2, frame]
                + 0.5 * (source[4, frame] + source[5, frame])
        case (4, 2):
            destination[0, frame] += 0.5 * (source[0, frame] + source[2, frame])
            destination[1, frame] += 0.5 * (source[1, frame] + source[3, frame])
        case (6, 2):
            destination[0, frame] += source[0, frame]
                + sqrt(0.5) * (source[2, frame] + source[4, frame])
            destination[1, frame] += source[1, frame]
                + sqrt(0.5) * (source[2, frame] + source[5, frame])
        case (6, 4):
            destination[0, frame] += source[0, frame] + sqrt(0.5) * source[2, frame]
            destination[1, frame] += source[1, frame] + sqrt(0.5) * source[2, frame]
            destination[2, frame] += source[4, frame]
            destination[3, frame] += source[5, frame]
        default:
            break
        }
    }
}
