import Dawn
import VectorMath

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(ucrt)
    import ucrt
#endif

/// Prints why the benchmark failed, for even a pipe to see: the throw that
/// follows ends the process, and with it what is buffered.
private func reportFailure(_ text: String) {
    print(text)
    #if canImport(Darwin) || canImport(Glibc) || canImport(ucrt)
        fflush(nil)
    #endif
}

extension LightLab {
    /// A view to time, and the hour to time it at.
    private struct BenchmarkView {
        var name: String
        var hour: Float
        var camera: Camera
        var walker: FirstPerson?
        /// Whether the focus crosses a chunk every frame, as moving fast would,
        /// to time loading voxels into the window.
        var scrolls = false
    }

    private static let benchmarkSize = (width: UInt32(2560), height: UInt32(1440))
    private static let warmUpFrames = 20
    private static let timedFrames = 120

    /// Times fixed views at a fixed size, away from the screen and its
    /// refresh, waiting for the GPU to finish every frame, and prints the
    /// median and the 95th percentile of each view. Throws if the GPU reports
    /// an error or the device is lost, as then nothing was really drawn.
    static func runBenchmark(
        device: Device, instance: Instance, renderer: Renderer, scene: Scene, format: TextureFormat
    ) async throws {
        let middle = scene.middleTileOffset
        let center = Camera(focus: Vector3(20 + middle, 1.5, 24 + middle))
        var close = Camera(focus: Vector3(30 + middle, 1, 30 + middle))
        close.zoom = 6
        close.yaw = -60 * .pi / 180
        close.targetYaw = close.yaw
        close.pitch = 25 * .pi / 180
        var far = center
        far.zoom = 30
        var walker = FirstPerson(feet: Vector3(24 + middle, Scene.streetLevel + 0.125, 23 + middle), yaw: 200 * .pi / 180)
        walker.pitch = 2 * .pi / 180
        let views = [
            BenchmarkView(name: "day", hour: 14, camera: center),
            BenchmarkView(name: "night", hour: 21, camera: center),
            BenchmarkView(name: "night close", hour: 21, camera: close),
            BenchmarkView(name: "night far", hour: 21, camera: far),
            BenchmarkView(name: "night first person", hour: 21, camera: center, walker: walker),
            BenchmarkView(name: "night scrolling", hour: 21, camera: center, scrolls: true),
        ]

        let size = Extent3D(width: benchmarkSize.width, height: benchmarkSize.height, depthOrArrayLayers: 1)
        let target = try device.createTexture(
            descriptor: TextureDescriptor(
                label: "benchmark", usage: .renderAttachment, dimension: .`2D`, size: size, format: format)
        ).createView()
        // Mapping this after each frame waits for the GPU to finish it.
        let fence = try device.createBuffer(descriptor: BufferDescriptor(usage: .copySrc, size: 4))
        let fenceCopy = try device.createBuffer(descriptor: BufferDescriptor(usage: [.mapRead, .copyDst], size: 4))
        let character = VoxelMesh()
        let schedule = ScheduleState(elapsed: 0.25)
        let clock = ContinuousClock()

        print("benchmark: \(benchmarkSize.width)x\(benchmarkSize.height), \(renderer.triangleCount) triangles, \(scene.lights.count) lamps")
        for view in views {
            let time = TimeOfDay(hour: view.hour)
            let lit = lighting(scene: scene, schedule: schedule.at(night: time.night))
            let frame = frameUniforms(
                scene: scene, time: time, lampCount: lit.litCount, camera: view.camera, walker: view.walker,
                aspect: Float(benchmarkSize.width) / Float(benchmarkSize.height))
            device.pushErrorScope(.validation)
            var samples: [Double] = []
            for index in 0..<(warmUpFrames + timedFrames) {
                let start = clock.now
                let encoder = try device.createCommandEncoder()
                try renderer.draw(
                    frame: frame,
                    focus: (view.walker?.eye ?? view.camera.focus) + Vector3(view.scrolls && index % 2 == 1 ? 16 : 0, 0, 0),
                    materials: lit.materials, lights: lit.lights, character: character, bloomStrength: 0.06,
                    into: target, width: benchmarkSize.width, height: benchmarkSize.height, encoder: encoder
                ) { _ in }
                encoder.copyBufferToBuffer(source: fence, destination: fenceCopy, size: 4)
                device.getQueue().submit([try encoder.finish()])
                let mapped = Flag()
                Task {
                    do {
                        try await fenceCopy.mapAsync(mode: .read)
                    } catch {
                        mapped.error = error
                    }
                    mapped.isSet = true
                }
                while !mapped.isSet {
                    instance.processEvents()
                    await Task.yield()
                }
                if let error = mapped.error {
                    reportFailure("benchmark failed at \(view.name): \(error)")
                    throw error
                }
                fenceCopy.unmap()
                if index >= warmUpFrames {
                    let (seconds, attoseconds) = (clock.now - start).components
                    samples.append(Double(seconds) * 1000 + Double(attoseconds) / 1e15)
                }
            }
            let scopeDone = Flag()
            var scopeError: DeviceError?
            Task {
                do {
                    scopeError = try await device.popErrorScope()
                } catch {
                    scopeDone.error = error
                }
                scopeDone.isSet = true
            }
            while !scopeDone.isSet {
                instance.processEvents()
                await Task.yield()
            }
            if let error = scopeDone.error ?? scopeError {
                reportFailure("benchmark failed at \(view.name): \(error)")
                throw error
            }

            samples.sort()
            let median = samples[samples.count / 2]
            let high = samples[samples.count * 95 / 100]
            func text(_ value: Double) -> String { "\(Double(Int(value * 10)) / 10)" }
            print("  \(view.name): min \(text(samples[0])) ms, median \(text(median)) ms, p95 \(text(high)) ms, \(renderer.drawnChunks) chunks, \(renderer.drawnTriangles) triangles in view")
        }
    }
}
