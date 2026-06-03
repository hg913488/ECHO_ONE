import SwiftUI
import AppKit

enum OverlayMessage: Equatable {
    case recording
    case instructionRecording
    case modelLoading
    case cleaningUp
    case transforming
    case transcribing
    case clipboardFallback
    case noSoundDetected
    case learnedCorrection(MisheardReplacement)

    var primaryText: String {
        switch self {
        case .recording:             return "Recording"
        case .instructionRecording:  return "Instruction mode"
        case .modelLoading:          return "Loading"
        case .cleaningUp:            return "Cleaning up"
        case .transforming:          return "Transforming"
        case .transcribing:          return "Transcribing"
        case .clipboardFallback:     return "Copied"
        case .noSoundDetected:       return "No sound"
        case .learnedCorrection:     return "Learned"
        }
    }
}

class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayPillView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentMessage: OverlayMessage?
    private var liveText: String = ""

    var onNoSoundSettingsTapped: (() -> Void)?
    var onStopTapped: (() -> Void)?

    func updateLiveText(_ text: String) {
        liveText = text
    }

    func show(message: OverlayMessage = .recording) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if let hostingView, let panel {
            let size = panelSize(for: message)
            hostingView.rootView = makeView(for: message)
            panel.setContentSize(size)
            panel.ignoresMouseEvents = message != .noSoundDetected
            panel.contentViewController?.view.frame = NSRect(origin: .zero, size: size)
            hostingView.frame = NSRect(origin: .zero, size: size)
            position(panel: panel)
            panel.orderFrontRegardless()
            currentMessage = message
            scheduleDismissIfNeeded(for: message)
            return
        }

        let size = panelSize(for: message)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = message != .noSoundDetected
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hosting = NSHostingView(rootView: makeView(for: message))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        let vc = NSViewController()
        vc.view = container
        panel.contentViewController = vc
        self.hostingView = hosting

        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel
        currentMessage = message
        scheduleDismissIfNeeded(for: message)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        currentMessage = nil
        liveText = ""
    }

    func dismiss(ifShowing message: OverlayMessage) {
        guard currentMessage == message else { return }
        dismiss()
    }

    private func makeView(for message: OverlayMessage) -> OverlayPillView {
        OverlayPillView(
            message: message,
            onTap: message == .noSoundDetected ? { [weak self] in self?.onNoSoundSettingsTapped?() } : nil
        )
    }

    private func position(panel: NSPanel) {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = (screenFrame.midX - panel.frame.width / 2).rounded()
            let y = (screenFrame.minY + 50).rounded()
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func panelSize(for message: OverlayMessage) -> NSSize {
        switch message {
        case .recording:
            return NSSize(width: 188, height: 128)
        case .clipboardFallback:
            return NSSize(width: 110, height: 44)
        case .learnedCorrection, .noSoundDetected:
            return NSSize(width: 180, height: 44)
        default:
            return NSSize(width: 172, height: 44)
        }
    }

    private func scheduleDismissIfNeeded(for message: OverlayMessage) {
        switch message {
        case .clipboardFallback, .learnedCorrection, .noSoundDetected:
            let delay: TimeInterval = message == .noSoundDetected ? 5 : 3
            let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        default:
            return
        }
    }
}

// MARK: - Main overlay view

struct OverlayPillView: View {
    let message: OverlayMessage
    var onTap: (() -> Void)?
    @State private var isPulsing = false

    var body: some View {
        Group {
            if message == .recording {
                RecordingCardView()
            } else if message == .cleaningUp {
                CleaningUpPillView()
            } else {
                pillView
            }
        }
        .onAppear { isPulsing = true }
    }

    // MARK: Pill — dark glass matching the recording card

    private var pillView: some View {
        HStack(spacing: 7) {
            leadingIndicator
            pillLabel
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 0)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(glassBackground(cornerRadius: 13))
        .overlay(glassBorder(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 3)
        .onTapGesture { onTap?() }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if message == .modelLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(.white.opacity(0.7))
        } else if case .learnedCorrection = message {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(teal)
        } else if message == .clipboardFallback {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(teal)
        } else {
            Circle()
                .fill(pillDotColor)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.35 : 1.0)
                .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: isPulsing)
        }
    }

    @ViewBuilder
    private var pillLabel: some View {
        let echoStyle = message == .transcribing || message == .clipboardFallback
        Text(echoStyle ? message.primaryText.uppercased() : message.primaryText)
            .font(.system(size: echoStyle ? 10 : 13, weight: .semibold))
            .tracking(echoStyle ? 1.5 : 0)
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize()
    }

    private var pillDotColor: Color {
        switch message {
        case .recording:                                      return .red
        case .instructionRecording:                           return .orange
        case .modelLoading, .noSoundDetected:                 return teal
        case .cleaningUp, .transcribing, .transforming,
             .clipboardFallback:                              return teal
        case .learnedCorrection:                              return teal
        }
    }

    private let teal = Color(red: 0.24, green: 0.83, blue: 0.70)
}

// MARK: - Cleaning up loading bar pill

private struct CleaningUpPillView: View {
    @State private var progress: CGFloat = 0
    private let accent = Color(red: 0.24, green: 0.83, blue: 0.70)

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.08))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.5), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .scaleEffect(x: progress, y: 1, anchor: .leading)
            }
            .padding(.horizontal, 16)
            .frame(width: 172, height: 44)
            .background(glassBackground(cornerRadius: 13))
            .overlay(glassBorder(cornerRadius: 13))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 3)
            .onAppear {
                withAnimation(.easeOut(duration: 3.5)) {
                    progress = 0.85
                }
            }
    }
}

// MARK: - Shared glass helpers

private func glassBackground(cornerRadius: CGFloat) -> some View {
    ZStack {
        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: cornerRadius)
        Color(red: 0.05, green: 0.12, blue: 0.14).opacity(0.20)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
}

private func glassBorder(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.6
        )
}

// MARK: - Glass recording card

private struct RecordingCardView: View {
    @State private var isPulsing = false
    @State private var startTime = Date()
    @State private var amplitudes: [CGFloat] = [0.30, 0.48, 0.68, 0.85, 1.00, 0.88, 0.65, 0.45, 0.28]

    private let accent = Color(red: 0.24, green: 0.83, blue: 0.70)
    private let bases: [CGFloat] = [0.30, 0.48, 0.68, 0.85, 1.00, 0.88, 0.65, 0.45, 0.28]
    private let maxBarWidth: CGFloat = 152

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white.opacity(0.75))
                Text("ECHO ONE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Spacer()

            // Waveform — primary focus
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<amplitudes.count, id: \.self) { i in
                    Capsule()
                        .fill(barColor(for: i))
                        .frame(width: max(12, amplitudes[i] * maxBarWidth), height: 2)
                        .animation(.easeInOut(duration: 0.22), value: amplitudes[i])
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Footer — tiny timer, minimal footprint
            TimelineView(.periodic(from: startTime, by: 1.0)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(startTime)))
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 3, height: 3)
                        .opacity(isPulsing ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    Text(formatTime(elapsed))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("·")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.22))
                    Text("Recording")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 10)
        }
        .frame(width: 188, height: 128)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 18)
                Color(red: 0.05, green: 0.12, blue: 0.14).opacity(0.52)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            accent
                .opacity(0.45)
                .frame(width: 120, height: 2)
                .blur(radius: 8)
                .padding(.bottom, 4)
        }
        .onAppear {
            isPulsing = true
            startTime = Date()
        }
        .onReceive(Timer.publish(every: 0.13, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                amplitudes = bases.map { $0 * CGFloat.random(in: 0.45...1.0) }
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        let dist = abs(CGFloat(index) - 4.0) / 4.0
        let tealMix = max(0, 1.0 - dist * 2.5)
        if tealMix > 0 {
            return accent.opacity(0.4 + 0.6 * tealMix)
        } else {
            return Color.white.opacity(0.14 + 0.16 * (1.0 - dist))
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - NSVisualEffectView bridge

final class RoundedVisualEffectView: NSVisualEffectView {
    var roundingRadius: CGFloat = 0 {
        didSet { updateMask() }
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard roundingRadius > 0, !bounds.isEmpty else { return }
        let img = NSImage(size: bounds.size, flipped: false) { [r = roundingRadius] rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: roundingRadius, left: roundingRadius,
                                     bottom: roundingRadius, right: roundingRadius)
        img.resizingMode = .stretch
        maskImage = img
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> RoundedVisualEffectView {
        let view = RoundedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.roundingRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: RoundedVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.roundingRadius = cornerRadius
    }
}
