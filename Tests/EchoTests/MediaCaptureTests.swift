@testable import Echo
import Testing

@MainActor
@Test func mediaStreamTrackCollectionMatchesCaptureInterface() throws {
    let first = try MediaStreamTrack(sampleRate: 48_000, channelCount: 1)
    let second = try MediaStreamTrack(sampleRate: 48_000, channelCount: 1)
    let stream = MediaStream(tracks: [first, first])
    var added: [String] = []
    var removed: [String] = []
    stream.onaddtrack = { added.append($0.id) }
    stream.onremovetrack = { removed.append($0.id) }

    #expect(stream.getTracks().count == 1)
    #expect(stream.getAudioTracks().count == 1)
    #expect(stream.getVideoTracks().isEmpty)
    #expect(stream.getTrackById(first.id) === first)
    #expect(stream.getTrackById(second.id) == nil)
    #expect(stream.active)

    stream.addTrack(first)
    stream.addTrack(second)
    stream.removeTrack(first)
    stream.removeTrack(first)
    #expect(added == [second.id])
    #expect(removed == [first.id])
    #expect(stream.getTracks().count == 1)

    let copy = MediaStream(stream)
    #expect(copy.id != stream.id)
    #expect(copy.getTrackById(second.id) === second)
    let clone = stream.clone()
    #expect(clone.id != stream.id)
    #expect(clone.getAudioTracks().count == 1)
    #expect(clone.getAudioTracks()[0].id != second.id)

    second.stop()
    #expect(second.readyState == .ended)
    #expect(!stream.active)
    #expect(copy.active == false)
    #expect(clone.active)
    clone.getAudioTracks()[0].stop()
}

@Test func clonedTrackKeepsCaptureSourceAlive() throws {
    let original = try MediaStreamTrack(sampleRate: 48_000, channelCount: 1)
    let clone = original.clone()
    original.stop()
    #expect(original.ended)
    #expect(!clone.ended)
    #expect(clone.getSettings().sampleRate == 48_000)
    #expect(clone.getSettings().channelCount == 1)

    [Float(0.25), 0.5].withUnsafeBufferPointer {
        #expect(original.appendInterleaved($0) == 2)
    }
    let output = AudioRenderQuantum(channelCapacity: 1, frameCount: 2)
    var cursor = 0.0
    clone.render(into: output, cursor: &cursor, outputSampleRate: 48_000)
    #expect(output.channelData(0)[0] == 0.25)
    #expect(output.channelData(0)[1] == 0.5)
    clone.stop()
}

@MainActor
@Test func mediaDevicesRejectsEmptyRequest() async throws {
    final class Backend: MediaCaptureBackend {
        var requested = false
        func enumerateDevices() async throws -> [MediaDeviceInfo] { [] }
        func getUserMedia(_ constraints: MediaStreamConstraints) async throws -> MediaStream {
            requested = true
            return MediaStream()
        }
    }
    let backend = Backend()
    let devices = MediaDevices(backend: backend)
    do {
        _ = try await devices.getUserMedia()
        Issue.record("Empty getUserMedia request succeeded")
    } catch {
        #expect(error as? WebAudioError == .notSupported)
    }
    #expect(!backend.requested)
    _ = try await devices.getUserMedia(MediaStreamConstraints(audio: .boolean(true)))
    #expect(backend.requested)
}
