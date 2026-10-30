import Foundation
import Testing

@testable import StbVorbis

// A quarter second at 44.1 kHz: a 440 Hz sine at half scale on the left,
// silence on the right. ffmpeg's own Vorbis encoder made it.
private let path = Bundle.module.path(forResource: "sine", ofType: "ogg", inDirectory: "Resources")!
private let sine = Array(FileManager.default.contents(atPath: path)!)

@Suite("stb_vorbis")
struct VorbisTests {
    @Test
    func decodesAllAtOnce() throws {
        let decoded = try decodeMemory(mem: sine)
        #expect(decoded.channels == 2 && decoded.sampleRate == 44_100)
        let left = stride(from: 0, to: decoded.output.count, by: 2).map { decoded.output[$0] }
        let right = stride(from: 1, to: decoded.output.count, by: 2).map { decoded.output[$0] }
        #expect(abs(left.count - 11_025) < 200)
        #expect(abs(Int(left.max()!) - 16_384) < 1_000)
        #expect(right.allSatisfy { abs(Int($0)) < 300 })
        #expect(try decodeFilename(filename: path).output == decoded.output)
    }

    @Test
    func pullsSamplesAChunkAtATime() throws {
        let vorbis = try openMemory(data: sine)
        #expect(getInfo(f: vorbis).sampleRate == 44_100)
        #expect(getInfo(f: vorbis).channels == 2)
        let length = streamLengthInSamples(f: vorbis)
        #expect(abs(Int(length) - 11_025) < 200)
        #expect(abs(streamLengthInSeconds(f: vorbis) - 0.25) < 0.01)

        var left: [Float] = []
        var right: [Float] = []
        while true {
            let chunk = getSamplesFloat(f: vorbis, channels: 2, numSamples: 4096)
            guard !chunk[0].isEmpty else { break }
            left += chunk[0]
            right += chunk[1]
        }
        #expect(left.count == Int(length))
        #expect(abs(left.max()! - 0.5) < 0.03)
        #expect(right.allSatisfy { abs($0) < 0.01 })
    }

    @Test
    func seeksToASample() throws {
        let vorbis = try openFilename(filename: path)
        let all = getSamplesFloatInterleaved(f: vorbis, channels: 2, numFloats: 2 * 20_000)
        try seek(f: vorbis, sampleNumber: 5_000)
        let after = getSamplesFloatInterleaved(f: vorbis, channels: 2, numFloats: 200)
        #expect(zip(after, all[10_000..<10_200]).allSatisfy { abs($0 - $1) < 1e-4 })

        try seekStart(f: vorbis)
        let shorts = getSamplesShortInterleaved(f: vorbis, channels: 2, numShorts: 200)
        #expect(zip(shorts, all.prefix(200)).allSatisfy { abs(Float($0) / 32_768 - $1) < 1e-3 })
    }

    @Test
    func mixesDownToTheChannelsAskedFor() throws {
        let vorbis = try openMemory(data: sine)
        let mono = getSamplesFloat(f: vorbis, channels: 1, numSamples: 1024)
        #expect(mono.count == 1 && mono[0].count == 1024)
    }

    @Test
    func failuresSayWhy() {
        #expect(throws: StbVorbisError.self) { try decodeMemory(mem: [1, 2, 3, 4]) }
        do {
            _ = try openMemory(data: Array("not an ogg file at all".utf8))
            Issue.record("opened garbage")
        } catch let error as StbVorbisError {
            #expect(error.operation == "stb_vorbis_open_memory")
            #expect(error.code != 0)
        } catch {
            Issue.record("\(error)")
        }
        #expect(throws: StbVorbisError(operation: "stb_vorbis_open_filename", code: 6)) {
            try openFilename(filename: "/nonexistent/sound.ogg")
        }
    }
}
