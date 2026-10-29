// Echo renders the audio itself, except in the browser, where Web/ hands it
// to the browser's Web Audio.
#if !os(Emscripten)
import Foundation

// The specification's StereoPannerNode panning, from a mono or stereo input
// to a stereo output.
enum StereoPanning {
    // `pan` gives the pan's computed value for each frame of the quantum.
    static func render(
        input: AudioRenderQuantum,
        output: AudioRenderQuantum,
        frame: UInt64,
        pan: (Int) -> Float
    ) {
        precondition((1 ... 2).contains(input.channelCount) && output.channelCount == 2)
        let left = output.channelData(0)
        let right = output.channelData(1)
        let isStereo = input.channelCount == 2
        let inputLeft = input.channelData(0)
        let inputRight = isStereo ? input.channelData(1) : inputLeft
        for index in 0 ..< input.frameCount {
            let pan = min(max(pan(index), -1), 1)
            let x = isStereo ? (pan <= 0 ? pan + 1 : pan) : (pan + 1) / 2
            let gainLeft = cos(x * .pi / 2)
            let gainRight = sin(x * .pi / 2)
            if !isStereo {
                left[index] = inputLeft[index] * gainLeft
                right[index] = inputLeft[index] * gainRight
            } else if pan <= 0 {
                left[index] = inputLeft[index] + inputRight[index] * gainLeft
                right[index] = inputRight[index] * gainRight
            } else {
                left[index] = inputLeft[index] * gainLeft
                right[index] = inputRight[index] + inputLeft[index] * gainRight
            }
        }
    }
}
#endif
