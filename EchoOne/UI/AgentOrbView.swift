import MetalKit
import SwiftUI

/// The Voice Agent orb: a glowing noise ring with an orbiting highlight, ported from HG's WebGL Orb
/// shader to Metal. It reacts to `level` (mic while HG talks, Ryan's audio while he replies).
/// Cursor reach, hover and 3D tilt from the web version are left out: the overlay isn't interactive.
enum AgentOrbMode {
    case listening, thinking, speaking
}

/// The three looks from HG's Orb Lab (echo-one-workfiles/orb-lab), picked in Settings → Voice Agent.
enum AgentOrbStyle: String, CaseIterable {
    case echoOne, original, ember

    static let defaultsKey = "voiceAgentOrbStyle"
    static let rippleDefaultsKey = "voiceAgentOrbRipple"

    static var current: AgentOrbStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AgentOrbStyle.init(rawValue:)) ?? .original
    }

    static var rippleIsOn: Bool {
        UserDefaults.standard.object(forKey: rippleDefaultsKey) as? Bool ?? current.ripplesByDefault
    }

    var name: String {
        switch self {
        case .echoOne: return "Echo One"
        case .original: return "Original"
        case .ember: return "Ember"
        }
    }

    /// Thumbnail in Assets.xcassets.
    var imageName: String {
        switch self {
        case .echoOne: return "OrbEchoOne"
        case .original: return "OrbOriginal"
        case .ember: return "OrbEmber"
        }
    }

    /// Ring colours: the two it swirls between, then the dark inner tone.
    var colors: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .echoOne: return (Self.rgb(0x00D2B9), Self.rgb(0x8A9BAF), Self.rgb(0x06343A))
        case .original: return (Self.rgb(0x9C43FE), Self.rgb(0x4CC2E9), Self.rgb(0x101499))
        case .ember: return (Self.rgb(0xFF5A3C), Self.rgb(0xFFC15E), Self.rgb(0x4A0B24))
        }
    }

    /// How far the ring bulges out with the voice (shader wobble = 1 + level × blob).
    var blob: Float {
        switch self {
        case .echoOne: return 3
        case .original: return 5
        case .ember: return 2.5
        }
    }

    /// Noise scale: lower makes bigger, slower lobes.
    var lobeSize: Float {
        switch self {
        case .echoOne: return 0.6
        case .original: return 0.4
        case .ember: return 0.9
        }
    }

    var ripplesByDefault: Bool { self == .ember }

    private static func rgb(_ hex: Int) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }
}

/// Matches `OrbUniforms` in the shader source below (same order, natural SIMD alignment).
struct OrbUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var awake: Float
    var scale: Float
    var swirl: Float
    var orbit: Float
    var reveal: Float
    var echo: SIMD2<Float>
    var opacity: Float
    var wobble: Float
    var freq: Float
    var color1: SIMD3<Float>
    var color2: SIMD3<Float>
    var color3: SIMD3<Float>
}

/// Owns the Metal pipeline and the animation state, so the orb keeps its phase when the overlay
/// swaps views (talking → thinking → reply) instead of replaying its intro each time.
@MainActor
final class AgentOrbRenderer: NSObject, MTKViewDelegate {
    /// Read every frame; falls back to `level` when unset.
    var levelSource: (() -> Float)?
    var level: Float = 0
    var mode: AgentOrbMode = .listening

    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?

    // Animation state, mirroring the web component's frame loop.
    private var time: Float = 0
    private var swirl: Float = 0
    private var orbit: Float = 0
    private var echo: Float = 1
    private var kick: Float = 2.5
    private var reveal: Float = 0
    private var smoothedLevel: Float = 0
    private var dimming: Float = 1
    private var lastFrame: CFTimeInterval = 0
    private var style = AgentOrbStyle.current
    private var ripple = AgentOrbStyle.rippleIsOn
    private var wordStarted = false
    private var sinceRipple: Float = 0

    private static let introSeconds: Float = 1.1

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        pipeline = device.flatMap(Self.makePipeline)
        super.init()
    }

    var isAvailable: Bool { pipeline != nil }

    /// Replays the intro (when the orb first appears for a new command).
    func restart() {
        style = AgentOrbStyle.current
        ripple = AgentOrbStyle.rippleIsOn
        reveal = 0
        kick = 2.5
        echo = 1
        lastFrame = 0
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        let now = CACurrentMediaTime()
        let dt = lastFrame == 0 ? Float(1.0 / 60.0) : min(max(Float(now - lastFrame), 0.0005), 0.05)
        lastFrame = now
        var uniforms = advance(dt: dt, drawableSize: view.drawableSize)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    func advance(dt: Float, drawableSize: CGSize) -> OrbUniforms {
        let target = min(max(levelSource?() ?? level, 0), 1)
        // Rise fast, fall slower, so syllables read as pulses.
        let tau: Float = target > smoothedLevel ? 0.05 : 0.18
        smoothedLevel += (target - smoothedLevel) * (1 - exp(-dt / tau))

        let baseSpeed: Float = mode == .thinking ? 0.45 : 1
        let targetDim: Float = mode == .thinking ? 0.7 : 1
        dimming += (targetDim - dimming) * (1 - exp(-dt / 0.3))

        let step = dt * baseSpeed * (1 + smoothedLevel * 1.6)
        time += step
        swirl += step * 2 * (1 + kick)
        echo = min(1, echo + dt / 1.2)
        orbit -= step
        orbit = atan2(sin(orbit), cos(orbit))
        kick *= exp(-dt * 2.5)
        if reveal < 1 { reveal = min(1, reveal + dt / Self.introSeconds) }
        if ripple {
            // A ring goes out at the start of each word.
            sinceRipple += dt
            if smoothedLevel > 0.45, !wordStarted, sinceRipple > 0.3 {
                echo = 0
                sinceRipple = 0
            }
            wordStarted = smoothedLevel > 0.45
        }

        let back = reveal - 1
        let grow = 1 + 2.2 * back * back * back + 1.2 * back * back
        let r = min(1, reveal / 0.55)
        let orbSize: Float = 0.82 * (1 + smoothedLevel * 0.09)

        return OrbUniforms(
            resolution: SIMD2(Float(max(1, drawableSize.width)), Float(max(1, drawableSize.height))),
            time: time,
            awake: smoothedLevel * 0.45,
            scale: 1 / (orbSize * (0.62 + 0.38 * grow)),
            swirl: swirl,
            orbit: orbit,
            reveal: r * r * (3 - 2 * r),
            echo: SIMD2(echo * 0.55, echo < 1 ? (1 - echo) * (1 - echo) : 0),
            opacity: dimming,
            wobble: 1 + smoothedLevel * style.blob,
            freq: style.lobeSize,
            color1: style.colors.0,
            color2: style.colors.1,
            color3: style.colors.2
        )
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: orbShaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("AgentOrb: Metal pipeline failed: \(error)")
            return nil
        }
    }
}

/// SwiftUI wrapper. Falls back to a plain gradient circle if Metal isn't available.
struct AgentOrbView: View {
    let renderer: AgentOrbRenderer

    var body: some View {
        if renderer.isAvailable {
            AgentOrbMetalView(renderer: renderer)
        } else {
            Circle()
                .fill(AngularGradient(colors: [Color(red: 0.61, green: 0.26, blue: 1.0),
                                               Color(red: 0.30, green: 0.76, blue: 0.91),
                                               Color(red: 0.61, green: 0.26, blue: 1.0)], center: .center))
                .padding(14)
                .blur(radius: 2)
        }
    }
}

private struct AgentOrbMetalView: NSViewRepresentable {
    let renderer: AgentOrbRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.delegate = renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        if view.delegate !== renderer { view.delegate = renderer }
    }
}

// MARK: - Shader (Metal translation of the WebGL Orb fragment shader)

private let orbShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct OrbUniforms {
    float2 resolution;
    float time;
    float awake;
    float scale;
    float swirl;
    float orbit;
    float reveal;
    float2 echo;
    float opacity;
    float wobble;
    float freq;
    float3 color1;
    float3 color2;
    float3 color3;
};

constant float kGlow = 1.0;
constant float kBleed = 1.0;
constant float kHighlight = 1.0;
constant float kTrail = 1.0;

vertex float4 orbVertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    return float4(p[vid], 0.0, 1.0);
}

static float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yxz + 19.19);
    return -1.0 + 2.0 * fract(float3(p3.x + p3.y, p3.x + p3.z, p3.y + p3.z) * p3.zyx);
}

static float snoise3(float3 p) {
    const float K1 = 0.333333333;
    const float K2 = 0.166666667;
    float3 i = floor(p + (p.x + p.y + p.z) * K1);
    float3 d0 = p - (i - (i.x + i.y + i.z) * K2);
    float3 e = step(float3(0.0), d0 - d0.yzx);
    float3 i1 = e * (1.0 - e.zxy);
    float3 i2 = 1.0 - e.zxy * (1.0 - e);
    float3 d1 = d0 - (i1 - K2);
    float3 d2 = d0 - (i2 - K1);
    float3 d3 = d0 - 0.5;
    float4 h = max(0.6 - float4(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), 0.0);
    float4 n = h * h * h * h * float4(dot(d0, hash33(i)), dot(d1, hash33(i + i1)), dot(d2, hash33(i + i2)), dot(d3, hash33(i + 1.0)));
    return dot(float4(31.316), n);
}

static float light1(float intensity, float attenuation, float dist) {
    return intensity / (1.0 + dist * attenuation);
}

static float light2(float intensity, float attenuation, float dist) {
    return intensity / (1.0 + dist * dist * attenuation);
}

static float4 drawOrb(float2 uv, constant OrbUniforms& u) {
    float len = length(uv);
    float2 dir = len > 0.0001 ? uv / len : float2(1.0, 0.0);
    float ang = atan2(dir.y, dir.x);
    float invLen = len > 0.0 ? 1.0 / len : 0.0;

    float n0 = snoise3(float3(uv * u.freq, u.time * 0.5)) * 0.5 + 0.5;
    float r0 = mix(0.8 - 0.04 * u.wobble, 0.8 + 0.04 * u.wobble, n0);
    float d0 = distance(uv, (r0 * invLen) * uv);
    float v0 = light1(1.0, 10.0 / kGlow, d0);
    v0 *= smoothstep(r0 * 1.05, r0, len);
    float reach = max(kBleed, 0.04);
    v0 *= smoothstep(r0 * (1.0 - 0.2 * reach), r0 * (1.0 - 0.05 * reach), len);
    float body = smoothstep(0.8 - 0.2 * reach, 0.8, len);
    float cl = cos(ang + u.swirl) * 0.5 + 0.5;

    float2 head = float2(cos(u.orbit), sin(u.orbit));
    float2 pos = head * r0;
    float d = distance(uv, pos);
    float lag = atan2(head.x * dir.y - head.y * dir.x, dot(dir, head));
    float trail = kTrail > 0.0 ? smoothstep(0.0, 0.35, lag) * exp(-max(lag, 0.0) * 2.6 / kTrail) : 0.0;
    float v1 = (light2(1.5, 5.0, d) + trail * 0.6) * kHighlight;
    v1 *= light1(1.0, 50.0, d0);
    float band = v0 * smoothstep(1.0, mix(0.6, 1.0, n0 * 0.5), len) * body;
    float heat = pow(clamp(band / 0.82, 0.0, 1.0), 3.0);
    float bloom = light2(1.0, 160.0 / kGlow, max(len - r0, 0.0)) * smoothstep(0.4, 0.0, len - r0) * step(r0, len);

    float v2 = smoothstep(1.0, mix(0.6, 1.0, n0 * 0.5), len);
    float v3 = body;

    float3 colBase = mix(u.color1, u.color2, cl);

    float echoD = abs(len - r0 - u.echo.x);
    float echo = light1(1.0, 60.0, echoD) * smoothstep(0.12, 0.0, echoD) * u.echo.y;

    float3 darkCol = mix(u.color3, colBase, v0);
    darkCol = (darkCol + v1) * v2 * v3 * (1.0 + u.awake) + mix(colBase, float3(1.0), 0.25) * heat * 0.28;
    darkCol = clamp(darkCol + colBase * (bloom * 0.1 + echo), 0.0, 1.0);

    float3 finalCol = darkCol;
    float alpha = max(max(finalCol.r, finalCol.g), finalCol.b);
    return float4(finalCol / (alpha + 1e-5), alpha);
}

fragment float4 orbFragment(float4 position [[position]], constant OrbUniforms& u [[buffer(0)]]) {
    // Metal's origin is top-left; flip to match gl_FragCoord.
    float2 fc = float2(position.x, u.resolution.y - position.y);
    float2 uv = (fc - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y) * 2.0;
    uv *= u.scale;

    float4 col = drawOrb(uv, u);
    float dither = (fract(sin(dot(fc, float2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    float alpha = clamp(col.a * u.reveal * u.opacity + dither, 0.0, 1.0);
    return float4(col.rgb * alpha * alpha, alpha);
}
"""
