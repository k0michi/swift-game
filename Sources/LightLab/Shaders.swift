/// The WGSL of the passes. The voxel textures are laid out as the grid is,
/// x fastest, then z, then y, so that they are indexed (x, z, y).
enum Shaders {
    /// What the scene's passes share: the frame, the materials, the lamps,
    /// the sun's shadow map and the voxels.
    static let scene = """
        struct Frame {
            viewProjection: mat4x4f,
            sunViewProjection: mat4x4f,
            // Toward the sun or moon.
            sunDirection: vec4f,
            sunColor: vec4f,
            skyColor: vec4f,
            horizonColor: vec4f,
            groundColor: vec4f,
            // The direction the camera looks.
            viewDirection: vec4f,
            // The number of lamps lit, the exposure, the strength of the
            // light of the sky, and the bias of the sun's shadow map.
            params: vec4f,
            // Voxels along x, y and z, and voxels a meter.
            gridSize: vec4f,
            // The eye, and 1 if the view is in perspective.
            eye: vec4f,
            // The width of a square of the lamps' grid, and how many squares
            // it is along x and z.
            lightGrid: vec4f,
        }

        @group(0) @binding(0) var<uniform> frame: Frame;
        // Each material's color in linear light and how bright it glows,
        // then its kind and roughness.
        @group(0) @binding(1) var<uniform> materials: array<vec4f, 256>;
        // Each lamp's position and reach, then its color times brightness.
        @group(0) @binding(2) var lightData: texture_2d<f32>;
        @group(0) @binding(3) var shadowMap: texture_depth_2d;
        @group(0) @binding(4) var shadowSampler: sampler_comparison;
        @group(0) @binding(5) var occupancy: texture_3d<u32>;
        @group(0) @binding(6) var skyVisibility: texture_3d<f32>;
        @group(0) @binding(7) var linearSampler: sampler;
        // For each square of the ground, where its lamps start in
        // lampIndices and how many there are.
        @group(0) @binding(8) var lampCells: texture_2d<u32>;
        @group(0) @binding(9) var lampIndices: texture_2d<u32>;

        fn lampTexel(texel: u32) -> vec4f {
            return textureLoad(lightData, vec2i(i32(texel % 256u), i32(texel / 256u)), 0);
        }

        fn lampIndex(position: u32) -> u32 {
            return textureLoad(lampIndices, vec2i(i32(position % 1024u), i32(position / 1024u)), 0).r;
        }

        // Where the lamps that reach a point start, and how many there are.
        fn lampsAt(world: vec3f) -> vec2u {
            let cell = vec2i(floor(world.xz / frame.lightGrid.x));
            return textureLoad(lampCells, clamp(cell, vec2i(0), vec2i(frame.lightGrid.yz) - 1), 0).rg;
        }

        struct VertexOutput {
            @builtin(position) clip: vec4f,
            @location(0) world: vec3f,
            @location(1) normal: vec3f,
            @location(2) @interpolate(flat, either) material: u32,
            @location(3) occlusion: f32,
        }

        @vertex
        fn vertexMain(
            @location(0) position: vec3f,
            @location(1) normal: vec4f,
            @location(2) info: vec4u
        ) -> VertexOutput {
            var output: VertexOutput;
            output.clip = frame.viewProjection * vec4f(position, 1.0);
            output.world = position;
            output.normal = normal.xyz;
            output.material = info.x;
            output.occlusion = f32(info.y) / 3.0;
            return output;
        }

        // The direction the camera looks at a point.
        fn viewAt(world: vec3f) -> vec3f {
            if frame.eye.w > 0.5 { return normalize(world - frame.eye.xyz); }
            return frame.viewDirection.xyz;
        }

        fn isOpaque(cell: vec3i) -> bool {
            let size = vec3i(frame.gridSize.xyz);
            if cell.y < 0 { return true; }
            if any(cell < vec3i(0)) || any(cell >= size) { return false; }
            return textureLoad(occupancy, vec3i(cell.x, cell.z, cell.y), 0).r == 1u;
        }

        // 1 if the straight path from start to end, in meters, passes no
        // opaque voxel, else 0: a walk through the voxels it crosses.
        fn clearPath(start: vec3f, end: vec3f) -> f32 {
            let scale = frame.gridSize.w;
            let a = start * scale;
            let delta = end * scale - a;
            let distance = length(delta);
            if distance < 1.0 { return 1.0; }
            let direction = delta / distance;
            let tiny = abs(direction) < vec3f(1e-6);
            let safe = select(direction, vec3f(1e-6), tiny);
            var cell = vec3i(floor(a));
            let stepSign = vec3i(sign(direction));
            let tDelta = abs(1.0 / safe);
            var tMax = select((vec3f(cell) + max(vec3f(stepSign), vec3f(0.0)) - a) / safe, vec3f(1e30), tiny);
            for (var i = 0; i < 256; i++) {
                var t: f32;
                if tMax.x < tMax.y && tMax.x < tMax.z {
                    cell.x += stepSign.x;
                    t = tMax.x;
                    tMax.x += tDelta.x;
                } else if tMax.y < tMax.z {
                    cell.y += stepSign.y;
                    t = tMax.y;
                    tMax.y += tDelta.y;
                } else {
                    cell.z += stepSign.z;
                    t = tMax.z;
                    tMax.z += tDelta.z;
                }
                // The lamp sits in the air beside its glowing voxels.
                if t >= distance - 0.75 { return 1.0; }
                if isOpaque(cell) { return 0.0; }
            }
            return 1.0;
        }

        // How much sunlight reaches a point, from 0 to 1, filtered over
        // nine texels of the shadow map.
        fn sunShadow(world: vec3f, normal: vec3f) -> f32 {
            let p = frame.sunViewProjection * vec4f(world + normal * 0.04, 1.0);
            let uv = vec2f(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
            let texel = 1.0 / f32(textureDimensions(shadowMap).x);
            var sum = 0.0;
            for (var y = -1; y <= 1; y++) {
                for (var x = -1; x <= 1; x++) {
                    sum += textureSampleCompareLevel(
                        shadowMap, shadowSampler, uv + vec2f(f32(x), f32(y)) * texel, p.z - frame.params.w);
                }
            }
            return sum / 9.0;
        }

        // How much of the sky a point sees, from the baked grid, sampled a
        // little off the surface.
        fn skyLight(world: vec3f, normal: vec3f) -> f32 {
            let meters = frame.gridSize.xyz / frame.gridSize.w;
            let p = (world + normal * 0.35) / meters;
            return textureSampleLevel(skyVisibility, linearSampler, vec3f(p.x, p.z, p.y), 0.0).r;
        }

        // The light of the sky and of the ground around, by which way a
        // surface faces.
        fn ambientColor(normal: vec3f) -> vec3f {
            let sky = mix(frame.horizonColor.rgb, frame.skyColor.rgb, max(normal.y, 0.0));
            return mix(frame.groundColor.rgb, sky, normal.y * 0.5 + 0.5);
        }

        // The light of the lamps on a point, each stopped by what is opaque
        // between them.
        fn lampLight(world: vec3f, normal: vec3f, occlusion: f32) -> vec3f {
            var sum = vec3f(0.0);
            let cell = lampsAt(world);
            for (var k = 0u; k < cell.y; k++) {
                let i = lampIndex(cell.x + k);
                let color = lampTexel(i * 2u + 1u).rgb;
                if color.r + color.g + color.b <= 0.0 { continue; }
                let lamp = lampTexel(i * 2u);
                let toLamp = lamp.xyz - world;
                let d = length(toLamp);
                if d >= lamp.w { continue; }
                let l = toLamp / d;
                let facing = dot(normal, l);
                if facing <= 0.0 { continue; }
                let window = pow(clamp(1.0 - pow(d / lamp.w, 4.0), 0.0, 1.0), 2.0);
                let falloff = window / (d * d + 0.5);
                let visible = clearPath(world + normal * 0.07, lamp.xyz);
                sum += color * facing * falloff * visible * mix(0.6, 1.0, occlusion);
            }
            return sum;
        }

        @fragment
        fn opaqueMain(input: VertexOutput) -> @location(0) vec4f {
            let material = materials[input.material * 2u];
            let surface = materials[input.material * 2u + 1u];
            let n = normalize(input.normal);
            let occlusion = mix(0.4, 1.0, input.occlusion);
            let shadow = sunShadow(input.world, n);
            let toSun = frame.sunDirection.xyz;
            let sun = frame.sunColor.rgb * max(dot(n, toSun), 0.0) * shadow;
            let ambient = ambientColor(n) * skyLight(input.world, n) * occlusion * frame.params.z;
            let lamps = lampLight(input.world, n, input.occlusion);
            var color = material.rgb * (sun + ambient + lamps) + material.rgb * material.w;
            // A highlight of the sun on smooth metal.
            let roughness = surface.y;
            if roughness < 0.6 {
                let h = normalize(toSun - viewAt(input.world));
                let shininess = mix(200.0, 8.0, roughness);
                color += frame.sunColor.rgb * shadow * pow(max(dot(n, h), 0.0), shininess) * (1.0 - roughness) * 0.5;
            }
            return vec4f(color, 1.0);
        }

        // Glass, mostly clear: it reflects the sky and the highlights of the
        // sun and the lamps, more at a glancing angle.
        @fragment
        fn glassMain(input: VertexOutput) -> @location(0) vec4f {
            let material = materials[input.material * 2u];
            var n = normalize(input.normal);
            let toEye = -viewAt(input.world);
            if dot(n, toEye) < 0.0 { n = -n; }
            let cosine = clamp(dot(n, toEye), 0.0, 1.0);
            let fresnel = 0.04 + 0.96 * pow(1.0 - cosine, 5.0);
            let r = reflect(-toEye, n);
            var reflection = ambientColor(r) * frame.params.z * 1.5;
            let shadow = sunShadow(input.world, n);
            reflection += frame.sunColor.rgb * shadow * pow(max(dot(r, frame.sunDirection.xyz), 0.0), 600.0) * 40.0;
            let cell = lampsAt(input.world);
            for (var k = 0u; k < cell.y; k++) {
                let i = lampIndex(cell.x + k);
                let lamp = lampTexel(i * 2u);
                let toLamp = lamp.xyz - input.world;
                let d = length(toLamp);
                if d >= lamp.w * 1.5 { continue; }
                let falloff = 1.0 / (d * d + 0.5);
                reflection += lampTexel(i * 2u + 1u).rgb * pow(max(dot(r, toLamp / d), 0.0), 300.0) * falloff * 30.0;
            }
            let tint = material.rgb * ambientColor(n) * frame.params.z * 0.15;
            let alpha = clamp(0.1 + fresnel, 0.0, 1.0);
            // Premultiplied: what it adds, and how much it covers.
            return vec4f(reflection * fresnel + tint * alpha, alpha);
        }
        """

    /// Depth from the sun, for its shadows.
    static let shadow = """
        struct Frame {
            viewProjection: mat4x4f,
            sunViewProjection: mat4x4f,
        }

        @group(0) @binding(0) var<uniform> frame: Frame;

        @vertex
        fn vertexMain(@location(0) position: vec3f) -> @builtin(position) vec4f {
            return frame.sunViewProjection * vec4f(position, 1.0);
        }
        """

    /// How much of the sky each cell of a coarse grid sees: the share of
    /// rays, spread over the upper half of directions, that leave the
    /// voxels without meeting anything opaque.
    static let skyVisibility = """
        @group(0) @binding(0) var occupancy: texture_3d<u32>;
        @group(0) @binding(1) var output: texture_storage_3d<rgba16float, write>;
        // The row of the output, along z, that this dispatch starts at.
        @group(0) @binding(2) var<uniform> slab: vec4u;

        const rayCount = 24u;

        fn isOpaque(cell: vec3i, size: vec3i) -> bool {
            if cell.y < 0 { return true; }
            if any(cell < vec3i(0)) || any(cell >= size) { return false; }
            return textureLoad(occupancy, vec3i(cell.x, cell.z, cell.y), 0).r == 1u;
        }

        // Whether a ray from a point, in voxels, leaves the grid unblocked.
        fn escapes(origin: vec3f, direction: vec3f, size: vec3i) -> bool {
            var cell = vec3i(floor(origin));
            if isOpaque(cell, size) { return false; }
            let tiny = abs(direction) < vec3f(1e-6);
            let safe = select(direction, vec3f(1e-6), tiny);
            let stepSign = vec3i(sign(direction));
            let tDelta = abs(1.0 / safe);
            var tMax = select((vec3f(cell) + max(vec3f(stepSign), vec3f(0.0)) - origin) / safe, vec3f(1e30), tiny);
            for (var i = 0; i < 400; i++) {
                if tMax.x < tMax.y && tMax.x < tMax.z {
                    cell.x += stepSign.x;
                    tMax.x += tDelta.x;
                } else if tMax.y < tMax.z {
                    cell.y += stepSign.y;
                    tMax.y += tDelta.y;
                } else {
                    cell.z += stepSign.z;
                    tMax.z += tDelta.z;
                }
                if any(cell < vec3i(0, -1, 0)) || any(cell >= size) { return true; }
                if isOpaque(cell, size) { return false; }
            }
            return true;
        }

        @compute @workgroup_size(4, 4, 4)
        fn main(@builtin(global_invocation_id) invocation: vec3u) {
            let id = invocation + vec3u(0u, slab.x, 0u);
            let dims = textureDimensions(output);
            if any(id >= dims) { return; }
            let fine = vec3i(textureDimensions(occupancy));
            let size = vec3i(fine.x, fine.z, fine.y);
            let factor = f32(fine.x) / f32(dims.x);
            // The cell's center, in voxels, as x, y, z.
            let origin = (vec3f(f32(id.x), f32(id.z), f32(id.y)) + 0.5) * factor;
            var open = 0.0;
            for (var k = 0u; k < rayCount; k++) {
                // Spread by a golden-angle spiral, denser overhead, as
                // light from the sky falls on a level surface.
                let u = (f32(k) + 0.5) / f32(rayCount);
                let sinTheta = sqrt(u);
                let cosTheta = sqrt(1.0 - u);
                let phi = f32(k) * 2.39996;
                let direction = vec3f(sinTheta * cos(phi), cosTheta, sinTheta * sin(phi));
                if escapes(origin, direction, size) { open += 1.0; }
            }
            textureStore(output, id, vec4f(open / f32(rayCount), 0.0, 0.0, 1.0));
        }
        """

    /// Bloom and the last pass to the screen: halving, then adding back up,
    /// then mapping light to the screen's colors.
    static let post = """
        struct VertexOutput {
            @builtin(position) position: vec4f,
            @location(0) uv: vec2f,
        }

        @vertex
        fn fullscreen(@builtin(vertex_index) index: u32) -> VertexOutput {
            let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u)) * 2.0 - 1.0;
            var output: VertexOutput;
            output.position = vec4f(corner, 0.0, 1.0);
            output.uv = vec2f(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);
            return output;
        }

        @group(0) @binding(0) var source: texture_2d<f32>;
        @group(0) @binding(1) var linearSampler: sampler;

        @fragment
        fn down(input: VertexOutput) -> @location(0) vec4f {
            let texel = 1.0 / vec2f(textureDimensions(source));
            var color = vec3f(0.0);
            for (var y = -1; y <= 1; y += 2) {
                for (var x = -1; x <= 1; x += 2) {
                    color += textureSampleLevel(source, linearSampler, input.uv + vec2f(f32(x), f32(y)) * texel, 0.0).rgb;
                }
            }
            return vec4f(min(color * 0.25, vec3f(200.0)), 1.0);
        }

        @fragment
        fn up(input: VertexOutput) -> @location(0) vec4f {
            let texel = 1.0 / vec2f(textureDimensions(source));
            var color = vec3f(0.0);
            for (var y = -1; y <= 1; y++) {
                for (var x = -1; x <= 1; x++) {
                    let weight = f32((2 - abs(x)) * (2 - abs(y)));
                    color += textureSampleLevel(source, linearSampler, input.uv + vec2f(f32(x), f32(y)) * texel, 0.0).rgb * weight;
                }
            }
            return vec4f(color / 16.0, 1.0);
        }

        @group(0) @binding(2) var bloom: texture_2d<f32>;
        // The exposure, the strength of bloom, and whether to encode for a
        // screen that does not.
        @group(0) @binding(3) var<uniform> settings: vec4f;

        // Narkowicz's fit of the ACES filmic curve.
        fn aces(x: vec3f) -> vec3f {
            return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
        }

        @fragment
        fn composite(input: VertexOutput) -> @location(0) vec4f {
            let scene = textureSampleLevel(source, linearSampler, input.uv, 0.0).rgb;
            let glow = textureSampleLevel(bloom, linearSampler, input.uv, 0.0).rgb;
            let color = aces((scene + glow * settings.y) * settings.x);
            if settings.z > 0.5 {
                return vec4f(pow(color, vec3f(1.0 / 2.2)), 1.0);
            }
            return vec4f(color, 1.0);
        }
        """
}
