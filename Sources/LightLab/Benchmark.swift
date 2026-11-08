import Dawn
import VectorMath

extension LightLab {
    /// A view to time, and the hour to time it at.
    private struct BenchmarkView {
        var name: String
        var hour: Float
        var camera: Camera
        var walker: FirstPerson?
    }

    private static let benchmarkSize = (width: UInt32(2560), height: UInt32(1440))
    private static let warmUpFrames = 20
    private static let timedFrames = 120

    /// Times fixed views at a fixed size, away from the screen and its
    /// refresh, waiting for the GPU to finish every frame, and prints the
    /// median and the 95th percentile of each view.
    static func runBenchmark(
        device: Device, instance: Instance, renderer: Renderer, scene: Scene, format: TextureFormat
    ) async throws {
        let center = Camera(focus: Vector3(20, 1.5, 24))
        var close = Camera(focus: Vector3(30, 1, 30))
        close.zoom = 6
        close.yaw = -60 * .pi / 180
        close.targetYaw = close.yaw
        close.pitch = 25 * .pi / 180
        var far = center
        far.zoom = 30
        var walker = FirstPerson(feet: Vector3(24, Scene.streetLevel + 0.125, 23), yaw: 200 * .pi / 180)
        walker.pitch = 2 * .pi / 180
        let views = [
            BenchmarkView(name: "day", hour: 14, camera: center),
            BenchmarkView(name: "night", hour: 21, camera: center),
            BenchmarkView(name: "night close", hour: 21, camera: close),
            BenchmarkView(name: "night far", hour: 21, camera: far),
            BenchmarkView(name: "night first person", hour: 21, camera: center, walker: walker),
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
            var samples: [Double] = []
            for index in 0..<(warmUpFrames + timedFrames) {
                let start = clock.now
                let encoder = try device.createCommandEncoder()
                try renderer.draw(
                    frame: frame, materials: lit.materials, lights: lit.lights, character: character, bloomStrength: 0.06,
                    into: target, width: benchmarkSize.width, height: benchmarkSize.height, encoder: encoder
                ) { _ in }
                encoder.copyBufferToBuffer(source: fence, destination: fenceCopy, size: 4)
                device.getQueue().submit([try encoder.finish()])
                let mapped = Flag()
                Task {
                    try? await fenceCopy.mapAsync(mode: .read)
                    mapped.isSet = true
                }
                while !mapped.isSet {
                    instance.processEvents()
                    await Task.yield()
                }
                fenceCopy.unmap()
                if index >= warmUpFrames {
                    let (seconds, attoseconds) = (clock.now - start).components
                    samples.append(Double(seconds) * 1000 + Double(attoseconds) / 1e15)
                }
            }
            samples.sort()
            let median = samples[samples.count / 2]
            let high = samples[samples.count * 95 / 100]
            func text(_ value: Double) -> String { "\(Double(Int(value * 10)) / 10)" }
            print("  \(view.name): median \(text(median)) ms, p95 \(text(high)) ms, \(lit.litCount) lamps lit")
        }
    }
}
