public final class AudioListener {
    public let positionX: AudioParam
    public let positionY: AudioParam
    public let positionZ: AudioParam
    public let forwardX: AudioParam
    public let forwardY: AudioParam
    public let forwardZ: AudioParam
    public let upX: AudioParam
    public let upY: AudioParam
    public let upZ: AudioParam

    init(context: BaseAudioContext) {
        func parameter(_ value: Float) -> AudioParam {
            AudioParam(graph: context.graph, defaultValue: value, minValue: -Float.greatestFiniteMagnitude, maxValue: Float.greatestFiniteMagnitude)
        }
        positionX = parameter(0)
        positionY = parameter(0)
        positionZ = parameter(0)
        forwardX = parameter(0)
        forwardY = parameter(0)
        forwardZ = parameter(-1)
        upX = parameter(0)
        upY = parameter(1)
        upZ = parameter(0)
    }

    public func setPosition(_ x: Float, _ y: Float, _ z: Float) {
        positionX.value = x
        positionY.value = y
        positionZ.value = z
    }

    public func setOrientation(_ x: Float, _ y: Float, _ z: Float, _ xUp: Float, _ yUp: Float, _ zUp: Float) {
        forwardX.value = x
        forwardY.value = y
        forwardZ.value = z
        upX.value = xUp
        upY.value = yUp
        upZ.value = zUp
    }
}
