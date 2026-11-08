import RealModule
import VectorMath

/// The light of the sky at an hour of the day: where the sun or the moon
/// is, and the colors of their light and of the sky.
struct TimeOfDay {
    /// From 0 up to 24.
    var hour: Float

    /// The sun's height above the horizon, from -1 at midnight to 1 at noon.
    private var sunHeight: Float {
        -Float.cos((hour / 24) * 2 * .pi)
    }

    /// From 0 by day to 1 by night, when lamps come on.
    var night: Float {
        1 - smoothstep(-0.12, 0.08, sunHeight)
    }

    /// The direction toward the sun, or by night, the moon, which shines
    /// from the opposite side.
    var lightDirection: Vector3<Float> {
        let angle = (hour / 24) * 2 * .pi
        // The sun rises in the east, +x, and sets in the west, leaning south.
        var direction = Vector3<Float>(Float.sin(angle), -Float.cos(angle), 0.45)
        if direction.y < 0.15 {
            // The moon, or a sun near the horizon, kept a little up so that
            // its shadows stay on the ground.
            direction = night > 0.5 ? Vector3(0.4, 0.8, 0.35) : Vector3(direction.x, 0.15, direction.z)
        }
        return normalize(direction)
    }

    /// The color and brightness of the sunlight or moonlight.
    var lightColor: Vector3<Float> {
        let day = smoothstep(-0.05, 0.25, sunHeight)
        let low = Vector3<Float>(1.0, 0.55, 0.3)
        let high = Vector3<Float>(1.0, 0.95, 0.88)
        let sun = (low + (high - low) * smoothstep(0.1, 0.5, sunHeight)) * 3.2 * day
        let moon = Vector3<Float>(0.35, 0.45, 0.7) * 0.18 * night
        return sun + moon
    }

    /// The sky's color overhead and at the horizon, which light the shade.
    var skyColors: (zenith: Vector3<Float>, horizon: Vector3<Float>) {
        let day = smoothstep(-0.1, 0.3, sunHeight)
        let dusk = max(1 - abs(sunHeight) * 5, 0)
        let zenithDay = Vector3<Float>(0.25, 0.45, 0.85)
        let horizonDay = Vector3<Float>(0.65, 0.75, 0.9)
        let zenithNight = Vector3<Float>(0.012, 0.018, 0.04)
        let horizonNight = Vector3<Float>(0.03, 0.035, 0.06)
        let duskColor = Vector3<Float>(0.9, 0.45, 0.25)
        var zenith = zenithNight + (zenithDay - zenithNight) * day
        var horizon = horizonNight + (horizonDay - horizonNight) * day
        horizon = horizon + (duskColor - horizon) * dusk * 0.7
        zenith = zenith + (duskColor * 0.4 - zenith) * dusk * 0.3
        return (zenith, horizon)
    }

    /// How bright an exposure the camera takes: more by night.
    var exposure: Float {
        0.55 + night * 1.6
    }
}

@inline(__always)
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
