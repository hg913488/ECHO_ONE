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
    case agentRecording
    case agentThinking
    case agentReply(String)

    /// Recording, Transcribing and Cleaning up are one object: the logo's capsule, stretching into the pill.
    var showsDictationMark: Bool {
        self == .recording || self == .transcribing || self == .cleaningUp
    }

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
        case .agentRecording:        return "Agent"
        case .agentThinking:         return "Thinking"
        case .agentReply(let text):  return text
        }
    }
}

@MainActor
class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayPillView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentMessage: OverlayMessage?
    private var liveText: String = ""

    var onNoSoundSettingsTapped: (() -> Void)?
    var onStopTapped: (() -> Void)?
    var onAgentReplyTapped: (() -> Void)?

    /// Voice Agent orb, created on first use so dictation never touches Metal.
    private lazy var orbRenderer = AgentOrbRenderer()
    /// Mic loudness for the dictation mark.
    let dictationLevel = DictationLevel()
    /// Where the mark is between recording and gone (the stretch into the pill, and how it leaves).
    private let markStage = DictationMarkStage()
    private var voiceActivity: AgentVoiceActivity?

    // MARK: Transcript peek (after dictating)

    private var peekPanel: NSPanel?
    private var peekState: TranscriptPeekState?
    private var peekDismissWorkItem: DispatchWorkItem?

    /// Drops what was just dictated from the notch. Folds away after 8 s, or waits for a click when the paste failed.
    func showTranscriptPeek(_ text: String, pasteFailed: Bool) {
        hideTranscriptPeek()
        guard let screen = NSScreen.main else { return }
        let notch = NotchGeometry(screen: screen)
        let height = notch.menuBarHeight + TranscriptPeekView.bodyHeight(for: text)
        let frame = NSRect(x: notch.frame.minX, y: screen.frame.maxY - height,
                           width: NotchGeometry.width, height: height)
        let state = TranscriptPeekState()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: TranscriptPeekView(
            text: text,
            pasteFailed: pasteFailed,
            state: state,
            menuBarHeight: notch.menuBarHeight,
            onCopy: { [weak self] in self?.copyPeek(text) },
            onClose: { [weak self] in self?.hideTranscriptPeek() },
            onHover: { [weak self] inside in self?.peekHover(inside, timed: !pasteFailed) }
        ))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        peekPanel = panel
        peekState = state
        if !pasteFailed { schedulePeekDismiss(after: 8) }
    }

    private func copyPeek(_ text: String) {
        guard let state = peekState, !state.copied else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.copied = true
        schedulePeekDismiss(after: 0.9)
    }

    /// Hovering holds a timed peek open; leaving gives it 3 more seconds.
    private func peekHover(_ inside: Bool, timed: Bool) {
        guard timed, peekState?.copied == false else { return }
        if inside {
            peekDismissWorkItem?.cancel()
        } else {
            schedulePeekDismiss(after: 3)
        }
    }

    private func schedulePeekDismiss(after delay: TimeInterval) {
        peekDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hideTranscriptPeek() }
        peekDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func hideTranscriptPeek() {
        peekDismissWorkItem?.cancel()
        peekDismissWorkItem = nil
        guard let panel = peekPanel else { return }
        peekState?.isClosing = true
        peekPanel = nil
        peekState = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            panel.orderOut(nil)
        }
    }

    // MARK: Notch teleprompter

    private var notchPanel: NSPanel?
    private var notchPresentation: NotchPresentation?

    private func updateNotch(for message: OverlayMessage) {
        if case .agentReply = message, let voiceActivity, VoiceAgent.showsReplyText {
            showNotch(activity: voiceActivity)
        } else {
            hideNotch()
        }
    }

    /// Unfurls from the hardware notch like Dayframe Cue: the panel is placed at full size and the
    /// SwiftUI shape inside grows from notch size. Screens without a notch get it from the top edge.
    private func showNotch(activity: AgentVoiceActivity) {
        guard notchPanel == nil, let screen = NSScreen.main else { return }
        hideTranscriptPeek()
        let geometry = NotchGeometry(screen: screen)
        let presentation = NotchPresentation()
        let panel = NSPanel(
            contentRect: geometry.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: NotchTeleprompterView(
            activity: activity,
            presentation: presentation,
            geometry: geometry,
            onTap: { [weak self] in self?.onAgentReplyTapped?() }
        ))
        panel.setFrame(geometry.frame, display: true)
        panel.orderFrontRegardless()
        notchPanel = panel
        notchPresentation = presentation
    }

    /// Text fades, then the shape shrinks back into the notch, then the panel goes.
    private func hideNotch() {
        guard let panel = notchPanel else { return }
        notchPresentation?.isClosing = true
        notchPanel = nil
        notchPresentation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            panel.orderOut(nil)
        }
    }

    func attachVoiceActivity(_ activity: AgentVoiceActivity) {
        voiceActivity = activity
        orbRenderer.levelSource = { [weak activity] in activity?.level ?? 0 }
    }

    private static func isAgentMessage(_ message: OverlayMessage) -> Bool {
        switch message {
        case .agentRecording, .agentThinking, .agentReply: return true
        default: return false
        }
    }

    private func prepareOrb(for message: OverlayMessage) {
        switch message {
        case .agentRecording:
            if let currentMessage, Self.isAgentMessage(currentMessage) {} else { orbRenderer.restart() }
            orbRenderer.mode = .listening
        case .agentThinking: orbRenderer.mode = .thinking
        case .agentReply: orbRenderer.mode = .speaking
        default: break
        }
    }

    func updateLiveText(_ text: String) {
        liveText = text
    }

    func show(message: OverlayMessage = .recording) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if message == .recording { hideTranscriptPeek() }
        updateMarkStage(for: message)

        prepareOrb(for: message)
        updateNotch(for: message)

        if let hostingView, let panel {
            let size = panelSize(for: message)
            panel.hasShadow = Self.hasWindowShadow(message)
            hostingView.rootView = makeView(for: message)
            panel.setContentSize(size)
            panel.ignoresMouseEvents = !Self.acceptsClicks(message)
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
        panel.hasShadow = Self.hasWindowShadow(message)
        panel.ignoresMouseEvents = !Self.acceptsClicks(message)
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

    private func updateMarkStage(for message: OverlayMessage) {
        switch message {
        case .recording:
            markStage.startRecording()
        case .transcribing, .cleaningUp:
            // Carry on from the mark already on screen (recording, or mid-fade); otherwise appear as the pill.
            let continuing = panel != nil && (currentMessage?.showsDictationMark ?? markStage.isWorking)
            markStage.work(word: message == .transcribing ? "TRANSCRIBING" : "CLEANING UP",
                           at: Date.timeIntervalSinceReferenceDate, continuing: continuing)
        default:
            break
        }
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if currentMessage == .transcribing || currentMessage == .cleaningUp, panel != nil {
            // The pill pops or fades away; anything shown meanwhile cancels this and reuses the panel.
            hideNotch()
            let exit = markStage.finish(at: Date.timeIntervalSinceReferenceDate)
            currentMessage = nil
            liveText = ""
            let workItem = DispatchWorkItem { [weak self] in self?.tearDown() }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + exit, execute: workItem)
            return
        }
        tearDown()
    }

    private func tearDown() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        hideNotch()
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

    func dismiss(ifShowing message: OverlayMessage, after delay: TimeInterval) {
        guard currentMessage == message else { return }
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.dismiss(ifShowing: message) }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// The orb and the dictation mark draw their own soft shadow; a window shadow would outline them.
    private static func hasWindowShadow(_ message: OverlayMessage) -> Bool {
        !message.showsDictationMark && !isAgentMessage(message)
    }

    private static func acceptsClicks(_ message: OverlayMessage) -> Bool {
        if message == .noSoundDetected { return true }
        if case .agentReply = message { return true }
        return false
    }

    private func makeView(for message: OverlayMessage) -> OverlayPillView {
        let onTap: (() -> Void)?
        switch message {
        case .noSoundDetected: onTap = { [weak self] in self?.onNoSoundSettingsTapped?() }
        case .agentReply: onTap = { [weak self] in self?.onAgentReplyTapped?() }
        default: onTap = nil
        }
        let isAgent = Self.isAgentMessage(message)
        return OverlayPillView(
            message: message,
            onTap: onTap,
            orb: isAgent ? orbRenderer : nil,
            activity: isAgent ? voiceActivity : nil,
            dictationLevel: dictationLevel,
            markStage: markStage
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
        case .recording, .transcribing, .cleaningUp:
            // One size for all three, wide enough for the stretched pill and its overshoot.
            return NSSize(width: 220, height: 68)
        case .clipboardFallback:
            return NSSize(width: 110, height: 44)
        case .learnedCorrection, .noSoundDetected:
            return NSSize(width: 180, height: 44)
        case .agentRecording, .agentThinking, .agentReply:
            return NSSize(width: 126, height: 126)
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
    var orb: AgentOrbRenderer?
    var activity: AgentVoiceActivity?
    var dictationLevel: DictationLevel?
    var markStage: DictationMarkStage?
    @State private var isPulsing = false

    var body: some View {
        Group {
            if message.showsDictationMark {
                DictationMarkView(level: dictationLevel ?? DictationLevel(), stage: markStage)
            } else if let orb {
                // Voice Agent: the orb alone at the bottom; the reply text drops from the notch.
                AgentOrbView(renderer: orb)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
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
        let echoStyle = message == .clipboardFallback
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
        case .learnedCorrection, .agentThinking:              return teal
        case .agentRecording, .agentReply:                    return agentPurple
        }
    }

    private let agentPurple = Color(red: 0.66, green: 0.55, blue: 0.98)
    private let teal = Color(red: 0.24, green: 0.83, blue: 0.70)
}

// MARK: - Shared glass helpers

/// Near-black, the same fill as the dictation mark's box, so the pills read on any wallpaper.
private func glassBackground(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color(red: 0.043, green: 0.047, blue: 0.055).opacity(0.94))
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

// MARK: - Dictation mark

/// Latest mic loudness (0–1) while dictating. AppState writes it on main; the mark reads it every frame.
final class DictationLevel: @unchecked Sendable {
    var value: Float = 0
}

/// Colours for the dictation mark, picked in Settings → General.
enum DictationMarkColour: String, CaseIterable {
    case bone, teal, ember, dusk

    static let defaultsKey = "dictationMarkColour"
    static var current: DictationMarkColour {
        DictationMarkColour(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .bone
    }

    var name: String { rawValue.capitalized }

    /// Bar colour at the start of the bar and at its longest reach, so louder reaches further into the gradient.
    var bar: (start: Color, end: Color) {
        switch self {
        case .bone:  return (Self.rgb(0xF5F2EC), Self.rgb(0xF5F2EC))
        case .teal:  return (Self.rgb(0x7FF0DF), Self.rgb(0x00C2AB))
        case .ember: return (Self.rgb(0xFFD3A1), Self.rgb(0xFF6A3D))
        case .dusk:  return (Self.rgb(0x9EDBFF), Self.rgb(0xA98BFF))
        }
    }

    var dot: Color {
        switch self {
        case .bone:  return Self.rgb(0x00D2B9)
        case .teal:  return Self.rgb(0x7FF0DF)
        case .ember: return Self.rgb(0xFF6A3D)
        case .dusk:  return Self.rgb(0xA98BFF)
        }
    }

    var glow: Color {
        switch self {
        case .bone, .teal: return Self.rgb(0x00D2B9)
        case .ember:       return Self.rgb(0xFF783C)
        case .dusk:        return Self.rgb(0x9682FF)
        }
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The Echo One logo, measured from AppIcon1024.png. Units are the top bar's length.
private enum EchoMark {
    static let rest: [CGFloat] = [1, 0.828, 1]
    static let curveOnTop = [true, false, false]
    static let barHeight: CGFloat = 0.16
    static let pitch: CGFloat = 0.394
    static let curveWidth: CGFloat = 0.17
    static let dotX: CGFloat = 1.265
    static let dotRadius: CGFloat = 0.089
    static let minLength: CGFloat = 0.3
    static let maxLength: CGFloat = 1.12
    static var height: CGFloat { 2 * pitch + barHeight }
    static var width: CGFloat { dotX + dotRadius }

    /// One bar: a wide curve on one left corner, square on the other, round right end.
    static func bar(x: CGFloat, y: CGFloat, length: CGFloat, height h: CGFloat, curveOnTop: Bool) -> Path {
        let rx = curveWidth / barHeight * h, r = h / 2, k: CGFloat = 0.5523
        let w = max(length, rx + r)
        var p = Path()
        if curveOnTop {
            p.move(to: CGPoint(x: x, y: y + h))
            p.addCurve(to: CGPoint(x: x + rx, y: y),
                       control1: CGPoint(x: x, y: y + h - k * h),
                       control2: CGPoint(x: x + rx - k * rx, y: y))
            p.addLine(to: CGPoint(x: x + w - r, y: y))
            p.addArc(center: CGPoint(x: x + w - r, y: y + r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        } else {
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + w - r, y: y))
            p.addArc(center: CGPoint(x: x + w - r, y: y + r), radius: r,
                     startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: x + rx, y: y + h))
            p.addCurve(to: CGPoint(x: x, y: y),
                       control1: CGPoint(x: x + rx - k * rx, y: y + h),
                       control2: CGPoint(x: x, y: y + k * h))
        }
        p.closeSubpath()
        return p
    }

    static let boxSize = CGSize(width: 80, height: 50)
    private static let rim = Gradient(colors: [
        Color(red: 0, green: 0.82, blue: 0.73), Color(red: 0.66, green: 0.55, blue: 1),
        Color(red: 1, green: 0.69, blue: 0.4), Color(red: 0, green: 0.82, blue: 0.73),
    ])

    /// Draws the logo centred in `size` on a near-black pill with a slowly turning holographic rim.
    /// `lengths` are bar lengths in logo units; `live` (0–1) drives the dot's halo and the rim's brightness.
    static func draw(in context: GraphicsContext, size: CGSize, unit u: CGFloat, lengths: [CGFloat],
                     live: CGFloat, colour: DictationMarkColour, time: Double) {
        let box = CGRect(x: (size.width - boxSize.width) / 2, y: (size.height - boxSize.height) / 2,
                         width: boxSize.width, height: boxSize.height)
        draw(in: context, box: box, origin: CGPoint(x: (size.width - width * u) / 2, y: (size.height - height * u) / 2),
             unit: u, lengths: lengths, live: live, haze: 1, colour: colour, time: time)
    }

    /// The same drawing with the capsule and the logo placed freely, for the stretch into the pill.
    /// The dot sits at the logo's spot, or rides the bottom bar's tip once that runs past it. `haze` (0–1) is the rim's blur.
    static func draw(in context: GraphicsContext, box: CGRect, origin: CGPoint, unit u: CGFloat, lengths: [CGFloat],
                     live: CGFloat, haze hazeAmount: CGFloat, colour: DictationMarkColour, time: Double) {
        let x0 = origin.x, y0 = origin.y
        let pill = Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous)
        var lifted = context
        lifted.addFilter(.shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2))
        lifted.fill(pill, with: .color(Color(red: 0.043, green: 0.047, blue: 0.055).opacity(0.94)))
        context.fill(pill, with: .linearGradient(Gradient(colors: [.white.opacity(0.07), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: box.minY),
                                                 endPoint: CGPoint(x: 0, y: box.minY + box.height * 0.45)))
        let turn = Angle.degrees(time.truncatingRemainder(dividingBy: 6) * 60)
        let rimShading = GraphicsContext.Shading.conicGradient(rim, center: CGPoint(x: box.midX, y: box.midY), angle: turn)
        if hazeAmount > 0.01 {
            var haze = context
            haze.addFilter(.blur(radius: 3))
            haze.opacity = (0.18 + 0.25 * live) * hazeAmount
            haze.stroke(pill, with: rimShading, lineWidth: 2)
        }
        var edge = context
        edge.opacity = 0.6 + 0.35 * live
        edge.fill(pill.strokedPath(StrokeStyle(lineWidth: 1)), with: rimShading)

        let h = barHeight * u
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [colour.bar.start, colour.bar.end]),
            startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0 + maxLength * u, y: 0))
        for i in 0..<3 {
            context.fill(bar(x: x0, y: y0 + CGFloat(i) * pitch * u, length: lengths[i] * u, height: h,
                          curveOnTop: curveOnTop[i]), with: shading)
        }

        let dot = CGPoint(x: x0 + max(dotX, lengths[2] + dotX - 1) * u, y: y0 + 2 * pitch * u + h / 2)
        let r = dotRadius * u * (1 + 0.15 * live)
        if live > 0.01 {
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 4 * r, y: dot.y - 4 * r, width: 8 * r, height: 8 * r)),
                         with: .radialGradient(Gradient(colors: [colour.glow.opacity(0.5 * live), colour.glow.opacity(0)]),
                                               center: dot, startRadius: 0, endRadius: 4 * r))
        }
        context.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)), with: .color(colour.dot))
    }
}

/// Bar motion for the dictation mark. Loudness flows from the top bar down to the bottom one; each bar
/// rises quickly and falls slowly like a level meter. Back to the plain logo after a short silence.
private final class DictationMarkMotion {
    private(set) var lengths = EchoMark.rest
    private(set) var talk: CGFloat = 0
    private(set) var glow: CGFloat = 0
    private var envelopes: [CGFloat] = [0, 0, 0]
    private var history: [(time: Double, level: CGFloat)] = []
    private var lastLoud: Double = -10
    private var lastTime: Double?
    private var peak: CGFloat = 0.15

    private static let falls: [CGFloat] = [0.14, 0.19, 0.24]

    func advance(to time: Double, level: CGFloat) {
        let dt = CGFloat(min(0.05, max(0, time - (lastTime ?? time))))
        lastTime = time
        // Auto-gain: scale to the loudest recent moment, so a normal speaking voice uses the bars' whole range.
        // The 0.12 floor keeps room noise from being blown up.
        peak = max(level, 0.12, peak * exp(-dt / 2))
        let level = level < 0.025 ? 0 : min(1, level / peak)
        history.append((time, level))
        while history.count > 2, history[1].time < time - 1 { history.removeFirst() }

        if level > 0.1 { lastLoud = time }
        talk = Self.ease(talk, toward: time - lastLoud < 0.45 ? 1 : 0, dt: dt, rise: 0.08, fall: 0.35)
        glow = Self.ease(glow, toward: level, dt: dt, rise: 0.04, fall: 0.25)
        for i in 0..<3 {
            envelopes[i] = Self.ease(envelopes[i], toward: pastLevel(at: time - Double(i) * 0.075),
                                     dt: dt, rise: 0.035, fall: Self.falls[i])
            let span = (EchoMark.maxLength - EchoMark.minLength) * (i == 1 ? 0.8 : 1)
            // The bottom bar stops short of the dot.
            let driven = min(i == 2 ? EchoMark.rest[2] : EchoMark.maxLength, EchoMark.minLength + envelopes[i] * span)
            let target = EchoMark.rest[i] * (1 - talk) + driven * talk
            lengths[i] = Self.ease(lengths[i], toward: target, dt: dt, rise: 0.03, fall: 0.03)
        }
    }

    /// Loudness at a past moment, interpolated so the cascade has no steps.
    private func pastLevel(at time: Double) -> CGFloat {
        for i in stride(from: history.count - 1, to: 0, by: -1) where history[i - 1].time <= time {
            let a = history[i - 1], b = history[i]
            let m = min(1, max(0, (time - a.time) / max(1e-6, b.time - a.time)))
            return a.level + (b.level - a.level) * CGFloat(m)
        }
        return 0
    }

    /// Exponential smoothing: stable at any frame rate.
    private static func ease(_ value: CGFloat, toward target: CGFloat, dt: CGFloat, rise: CGFloat, fall: CGFloat) -> CGFloat {
        value + (target - value) * (1 - exp(-dt / (target > value ? rise : fall)))
    }
}

/// The dictation overlay: the Echo One logo above the Dock, its bars moving with your voice.
/// With a `stage`, it then stretches into the Transcribing / Cleaning up pill.
struct DictationMarkView: View {
    let level: DictationLevel
    var colour: DictationMarkColour = .current
    /// Settings thumbnails draw the logo at rest.
    var still = false
    var unit: CGFloat = 22
    var stage: DictationMarkStage?

    @State private var motion = DictationMarkMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                if !still {
                    motion.advance(to: now, level: CGFloat(level.value))
                }
                if let stage, stage.isWorking {
                    DictationPill.draw(in: context, size: size, stage: stage, lengths: motion.lengths,
                                       live: motion.glow * motion.talk, colour: colour, time: now,
                                       reduceMotion: reduceMotion)
                } else {
                    EchoMark.draw(in: context, size: size, unit: unit, lengths: motion.lengths,
                                  live: motion.glow * motion.talk, colour: colour,
                                  time: still ? 0.75 : now)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Where the dictation mark is after you stop talking. Times are `Date.timeIntervalSinceReferenceDate`.
/// The bars settle for `threshold`; if the text is still being worked on then, the capsule stretches into the pill.
/// If it's done before that, the bottom bar pops out a little and the capsule fades.
final class DictationMarkStage {
    static let threshold: Double = 0.3
    static let stretch: Double = 0.8
    static let fade: Double = 0.3
    static let pop: Double = 0.45
    static let wordChange: Double = 0.4

    enum Exit { case pop, fade }

    private(set) var stretchStart: Double?
    private(set) var word = ""
    private(set) var wordWidth: CGFloat = 0
    private(set) var previousWidth: CGFloat?
    private(set) var previousWord: String?
    private(set) var wordChangedAt: Double = 0
    private(set) var exitStart: Double?
    private(set) var exit: Exit = .fade

    var isWorking: Bool { stretchStart != nil }

    func startRecording() {
        stretchStart = nil
        previousWord = nil
        previousWidth = nil
        exitStart = nil
    }

    /// `continuing`: the recording mark (or this pill) is on screen, so stretch from it; otherwise appear stretched.
    func work(word: String, at now: Double, continuing: Bool) {
        exitStart = nil
        guard let stretchStart, continuing else {
            stretchStart = continuing ? now + Self.threshold : now - Self.stretch
            previousWord = nil
            setWord(word)
            return
        }
        guard word != self.word else { return }
        if now < stretchStart {
            setWord(word)  // nothing written yet: just use the new word
        } else {
            previousWord = self.word
            previousWidth = wordWidth
            wordChangedAt = now
            setWord(word)
        }
    }

    /// Starts the exit and returns how long it takes, so the panel can close after it.
    func finish(at now: Double) -> TimeInterval {
        guard let stretchStart else { return 0 }
        if now < stretchStart {
            exit = .pop
            exitStart = now
            return Self.pop
        }
        exit = .fade
        let start = max(now, stretchStart + Self.stretch)  // a stretch already under way completes first
        exitStart = start
        return start - now + Self.fade
    }

    private func setWord(_ word: String) {
        self.word = word
        wordWidth = DictationPill.wordWidth(word)
        if previousWord == nil { previousWidth = nil }
    }
}

/// Draws the capsule stretching into the pill: the logo shrinks to the word's capital height and moves left,
/// and the bottom bar runs out under the word, writing it as the dot passes. Then the bar keeps going as the loader.
enum DictationPill {
    static let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    static let tracking: CGFloat = 1.5
    static let gap: CGFloat = 9           // logo to word
    static let sidePadding: CGFloat = 26
    static let height: CGFloat = 44
    static let loop: Double = 2.6
    static let restUnit: CGFloat = 22
    /// Logo unit at which the top two bars match the word's capital height.
    static var unit: CGFloat { font.capHeight / (EchoMark.pitch + EchoMark.barHeight) }

    static func wordWidth(_ word: String) -> CGFloat {
        let attributed = NSAttributedString(string: word, attributes: [.font: font, .kern: tracking])
        return attributed.size().width - tracking  // no trailing letter space
    }

    static func draw(in context: GraphicsContext, size: CGSize, stage: DictationMarkStage, lengths: [CGFloat],
                     live: CGFloat, colour: DictationMarkColour, time t: Double, reduceMotion: Bool) {
        guard let stretchStart = stage.stretchStart else { return }
        let popping = stage.exit == .pop && stage.exitStart != nil
        let stretchEnd = stretchStart + DictationMarkStage.stretch

        var m = popping ? 0 : clamp((t - stretchStart) / DictationMarkStage.stretch)
        if reduceMotion && !popping && t >= stretchStart { m = 1 }
        let eased = outCubic(m), springy = outBack(m)

        let change = stage.previousWidth == nil ? 1 : clamp((t - stage.wordChangedAt) / DictationMarkStage.wordChange)
        let wordWidth = lerp(stage.previousWidth ?? stage.wordWidth, stage.wordWidth, inOutCubic(change))

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let small = unit
        let u = lerp(restUnit, small, eased)
        let groupWidth = small + gap + wordWidth
        let width = lerp(EchoMark.boxSize.width, groupWidth + 2 * sidePadding, springy)
        let height = lerp(EchoMark.boxSize.height, Self.height, eased)
        let x0 = lerp(center.x - EchoMark.width * restUnit / 2, center.x - groupWidth / 2, eased)
        let y0 = center.y - EchoMark.height * u / 2

        // Bottom bar, in logo units at the current size; `full` puts the dot just past the last letter.
        let dotGap = EchoMark.dotX - 1
        let full = (u + gap + wordWidth - 1) / u - dotGap
        var top = Array(lengths.prefix(2))
        let bottom: CGFloat
        if popping, let exitStart = stage.exitStart {
            bottom = lengths[2] + 0.55 * outCubic(clamp((t - exitStart) / 0.18))
        } else if t < stretchStart {
            bottom = lengths[2]
        } else {
            if m < 1 {
                bottom = lerp(EchoMark.rest[2], full, inOutCubic(clamp((m - 0.12) / 0.88)))
            } else if reduceMotion {
                bottom = full
            } else {
                // Loader: start at full, hold, pull back into the logo, rest, run out again.
                let p = CGFloat((0.5 + (t - stretchEnd) / loop).truncatingRemainder(dividingBy: 1))
                let e = p < 0.5 ? inOutCubic(p / 0.5) : p < 0.57 ? 1 : p < 0.92 ? 1 - inOutCubic((p - 0.57) / 0.35) : 0
                bottom = lerp(1, full, e)
            }
            if !reduceMotion {  // the top two bars keep a quiet cascade
                let settle = clamp((t - stretchStart) / 0.6)
                for i in 0..<2 {
                    let swing = 0.5 + 0.5 * sin((t - stretchStart) * 2 * .pi * 0.75 - Double(i) * 0.75 - .pi / 2)
                    top[i] = lerp(lengths[i], EchoMark.rest[i] * (0.84 + 0.16 * CGFloat(swing)), settle)
                }
            }
        }

        // Exit: fade and shrink a touch.
        var alpha: CGFloat = 1
        if let exitStart = stage.exitStart {
            let fadeStart = popping ? exitStart + 0.15 : exitStart
            alpha = 1 - clamp((t - fadeStart) / DictationMarkStage.fade)
        }
        var ctx = context
        ctx.opacity = Double(alpha)
        let scale = 1 - 0.04 * (1 - alpha)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -center.x, y: -center.y)

        EchoMark.draw(in: ctx, box: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                      origin: CGPoint(x: x0, y: y0), unit: u, lengths: top + [bottom],
                      live: live, haze: popping ? 1 : 1 - eased, colour: colour, time: t)

        guard !popping, t >= stretchStart else { return }
        // The word: written in behind the dot during the stretch, then a shine riding above the dot.
        let dotX = x0 + (bottom + dotGap) * u
        let origin = CGPoint(x: x0 + u + gap, y: y0)  // capital tops line up with the top bar
        let writing = m < 1
        // A new word (TRANSCRIBING → CLEANING UP): the old one fades out, then the new one fades in.
        if let previous = stage.previousWord, change < 0.5 {
            drawWord(previous, in: ctx, at: origin, dotX: dotX, writing: writing, alpha: 1 - change * 2)
        }
        drawWord(stage.word, in: ctx, at: origin, dotX: dotX, writing: writing,
                 alpha: stage.previousWord == nil ? 1 : max(0, change * 2 - 1))
    }

    private static func drawWord(_ word: String, in context: GraphicsContext, at origin: CGPoint, dotX: CGFloat,
                                 writing: Bool, alpha: CGFloat) {
        var ctx = context
        ctx.opacity *= Double(alpha)
        var text = ctx.resolve(Text(word).font(.system(size: 10, weight: .semibold)).tracking(tracking))
        let base = Color.white.opacity(writing ? 0.86 : 0.8)
        let stops: [Gradient.Stop] = writing
            ? [.init(color: base, location: 0), .init(color: base, location: 0.3),
               .init(color: Color(red: 0.84, green: 0.98, blue: 0.95), location: 0.42),
               .init(color: .white.opacity(0), location: 0.5), .init(color: .white.opacity(0), location: 1)]
            : [.init(color: base, location: 0), .init(color: base, location: 0.25), .init(color: .white, location: 0.42),
               .init(color: Color(red: 0.77, green: 0.97, blue: 0.93), location: 0.5), .init(color: .white, location: 0.58),
               .init(color: base, location: 0.75), .init(color: base, location: 1)]
        text.shading = .linearGradient(Gradient(stops: stops),
                                       startPoint: CGPoint(x: dotX - 20, y: 0), endPoint: CGPoint(x: dotX + 20, y: 0))
        let box = CGSize(width: 400, height: 40)
        let baseline = text.firstBaseline(in: box)
        ctx.draw(text, at: CGPoint(x: origin.x, y: origin.y + font.capHeight - baseline), anchor: .topLeading)
    }

    private static func clamp(_ x: Double) -> CGFloat { CGFloat(min(1, max(0, x))) }
    private static func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { a + (b - a) * x }
    private static func outCubic(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
    private static func inOutCubic(_ x: CGFloat) -> CGFloat { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private static func outBack(_ x: CGFloat) -> CGFloat {
        let c1: CGFloat = 0.9, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

// MARK: - Transcript peek: what you just dictated, from the notch

/// Whether the notch shows the dictated text afterwards. Picked in Settings → General.
enum DictationNotchMode: String, CaseIterable {
    case everyDictation, pasteFails, off

    static let defaultsKey = "dictationNotchMode"
    static var current: DictationNotchMode { stored(UserDefaults.standard.string(forKey: defaultsKey)) }

    /// Nothing stored (or an unknown value) means "only when paste fails".
    static func stored(_ rawValue: String?) -> DictationNotchMode {
        DictationNotchMode(rawValue: rawValue ?? "") ?? .pasteFails
    }

    var title: String {
        switch self {
        case .everyDictation: return "Every time"
        case .pasteFails: return "If paste fails"
        case .off: return "Off"
        }
    }

    func shows(pasteFailed: Bool) -> Bool {
        switch self {
        case .everyDictation: return true
        case .pasteFails: return pasteFailed
        case .off: return false
        }
    }
}

final class TranscriptPeekState: ObservableObject {
    @Published var isClosing = false
    @Published var copied = false
}

/// Same shape and unfurl as the Voice Agent's notch, holding the dictated text. Click anywhere copies.
private struct TranscriptPeekView: View {
    let text: String
    let pasteFailed: Bool
    @ObservedObject var state: TranscriptPeekState
    let menuBarHeight: CGFloat
    var onCopy: () -> Void
    var onClose: () -> Void
    var onHover: (Bool) -> Void

    // 0 = notch size, 1 = full panel
    @State private var expansion: CGFloat = 0
    @State private var contentVisible = false
    @State private var arrivalSweep: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    private static let sideInset: CGFloat = 16 + 18
    private static let bottomPadding: CGFloat = 14
    private let teal = Color(red: 0.24, green: 0.83, blue: 0.70)

    /// Height below the menu bar: up to three lines of text plus padding.
    static func bodyHeight(for text: String) -> CGFloat {
        let width = NotchGeometry.width - sideInset * 2
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lines = min(3, max(1, (bounds.height / lineHeight).rounded(.up)))
        return lines * lineHeight + bottomPadding
    }

    var body: some View {
        GeometryReader { proxy in
            let notch = NotchGeometry.notchSize
            let currentHeight = notch.height + (proxy.size.height - notch.height) * expansion
            let currentWidth = notch.width + (proxy.size.width - notch.width) * expansion
            let shape = DynamicIslandShape(topInset: 8 + 8 * expansion, bottomRadius: 8 + 16 * expansion)

            ZStack(alignment: .top) {
                shape.fill(.black)
                    .frame(width: currentWidth, height: currentHeight)

                if contentVisible {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .frame(height: menuBarHeight)
                            .opacity(currentWidth >= 400 ? 1 : 0)
                        Text(text)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Self.sideInset)
                    .frame(width: currentWidth, height: proxy.size.height, alignment: .top)
                    .clipped()
                    .transition(.offset(y: -9).combined(with: .opacity))
                }

                NotchArrivalSweep(progress: arrivalSweep)
                    .frame(width: currentWidth, height: currentHeight)
            }
            .clipShape(shape)
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .onHover(perform: onHover)
        .onAppear(perform: open)
        .onChange(of: state.isClosing) { _, closing in
            if closing { close() }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(teal)
                .frame(width: 4, height: 4)
            Text(pasteFailed ? "Not pasted" : "Dictated")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            if state.copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(teal)
            } else {
                Text("Click to copy")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    /// Unfurls from the notch like the Voice Agent reply, then the text follows.
    private func open() {
        if reduceMotion {
            expansion = 1
            contentVisible = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { expansion = 1 }
        withAnimation(.easeInOut(duration: 0.58).delay(0.10)) { arrivalSweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.3)) { contentVisible = true }
        }
    }

    /// Text fades first, then the shape folds back into the notch.
    private func close() {
        withAnimation(.easeIn(duration: 0.15)) { contentVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.3)) { expansion = 0 }
        }
    }
}

// MARK: - Voice Agent reply: teleprompter that unfurls from the notch
// Notch shape and open/close choreography follow HG's Dayframe Cue (a fork of f/textream, MIT License,
// Copyright (c) Fatih Kadir Akın), including its Dynamic Island shape, arrival wash and sweep.

/// Where the notch is on this screen, and the panel that hangs from it.
struct NotchGeometry {
    let hasNotch: Bool
    let menuBarHeight: CGFloat
    let frame: NSRect

    static let width: CGFloat = 464        // Dayframe Cue's default
    static let textAreaHeight: CGFloat = 114  // three teleprompter lines + the step line
    static let notchSize = CGSize(width: 200, height: 37)

    init(screen: NSScreen) {
        let screenFrame = screen.frame
        hasNotch = screen.safeAreaInsets.top > 0
        menuBarHeight = max(screenFrame.maxY - screen.visibleFrame.maxY, 24)
        let height = menuBarHeight + Self.textAreaHeight
        frame = NSRect(x: screenFrame.midX - Self.width / 2, y: screenFrame.maxY - height,
                       width: Self.width, height: height)
    }
}

final class NotchPresentation: ObservableObject {
    @Published var isClosing = false
}

/// Concave top corners that melt into the bezel, rounded bottom corners.
private struct DynamicIslandShape: Shape {
    var topInset: CGFloat = 16
    var bottomRadius: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topInset, bottomRadius) }
        set {
            topInset = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, t = topInset, br = bottomRadius
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - br))
        p.addQuadCurve(to: CGPoint(x: t + br, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - br), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Wash along the lower edge in the orb's own colours (navy #101499, purple #9c43fe, cyan #4cc2e9),
/// so the notch and the talking ring read as one voice.
private struct NotchEdgeGlow: View {
    var intensity: Double

    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 0x10/255, green: 0x14/255, blue: 0x99/255), location: 0),
            .init(color: Color(red: 0x9c/255, green: 0x43/255, blue: 0xfe/255), location: 0.28),
            .init(color: Color(red: 0x4c/255, green: 0xc2/255, blue: 0xe9/255), location: 0.5),
            .init(color: Color(red: 0x9c/255, green: 0x43/255, blue: 0xfe/255), location: 0.72),
            .init(color: Color(red: 0x10/255, green: 0x14/255, blue: 0x99/255), location: 1)
        ], startPoint: .leading, endPoint: .trailing)
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .white.opacity(0.05), location: 0.34),
            .init(color: .white.opacity(0.24), location: 0.72),
            .init(color: .white.opacity(0.65), location: 1)
        ], startPoint: .top, endPoint: .bottom))
        // Fades out toward both ends instead of running edge to edge.
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .white, location: 0.3),
            .init(color: .white, location: 0.7),
            .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing))
        .opacity(intensity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The edge glow breathes with Ryan's voice, read from the live level only here.
private struct VoiceEdgeGlow: View {
    @ObservedObject var activity: AgentVoiceActivity
    var isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensity: Double {
        let level = Double(activity.level)
        guard isEnabled, level > 0.05 else { return 0 }
        return reduceMotion ? 0.7 : min(0.9, 0.62 + level * 0.6)
    }

    var body: some View {
        NotchEdgeGlow(intensity: intensity)
            .animation(reduceMotion ? nil : .easeOut(duration: intensity > 0 ? 0.2 : 0.65), value: intensity)
    }
}

/// One brief highlight travels across the lower lip as the panel opens.
private struct NotchArrivalSweep: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .white.opacity(0.55), .white.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 96, height: 2)
                .position(x: -50 + (geometry.size.width + 100) * progress, y: geometry.size.height - 2)
        }
        .opacity(progress > 0 && progress < 1 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NotchTeleprompterView: View {
    @ObservedObject var activity: AgentVoiceActivity
    @ObservedObject var presentation: NotchPresentation
    let geometry: NotchGeometry
    var onTap: (() -> Void)?

    // 0 = notch size, 1 = full panel
    @State private var expansion: CGFloat = 0
    @State private var contentVisible = false
    @State private var arrivalGlow = 0.0
    @State private var arrivalSweep: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let topInset: CGFloat = 16
    private let collapsedInset: CGFloat = 8
    private var currentTopInset: CGFloat { collapsedInset + (topInset - collapsedInset) * expansion }
    private var currentBottomRadius: CGFloat { 8 + (30 - 8) * expansion }

    var body: some View {
        GeometryReader { proxy in
            let notch = NotchGeometry.notchSize
            let currentHeight = notch.height + (proxy.size.height - notch.height) * expansion
            let currentWidth = notch.width + (proxy.size.width - notch.width) * expansion
            let shape = DynamicIslandShape(topInset: currentTopInset, bottomRadius: currentBottomRadius)

            ZStack(alignment: .top) {
                shape.fill(.black)
                    .frame(width: currentWidth, height: currentHeight)

                if contentVisible {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.65, green: 0.60, blue: 0.86))
                                .frame(width: 4, height: 4)
                            Text("Claude")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 0)
                            Text("Click for full transcript")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 18)
                        .frame(height: geometry.menuBarHeight)
                        .opacity(currentWidth >= 400 ? 1 : 0)

                        TeleprompterText(activity: activity)
                            .frame(height: TeleprompterText.lineHeight * 3)
                            .padding(.horizontal, 18)

                        AgentStepLine(activity: activity)
                            .frame(height: 16)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 8)
                    }
                    .padding(.horizontal, topInset)
                    .frame(width: currentWidth, height: proxy.size.height)
                    .clipped()
                    .transition(.offset(y: -9).combined(with: .opacity))
                }

                VoiceEdgeGlow(activity: activity, isEnabled: contentVisible)
                    .frame(width: currentWidth, height: 44)
                    .offset(y: currentHeight - 44)

                NotchEdgeGlow(intensity: arrivalGlow)
                    .frame(width: currentWidth, height: 44)
                    .offset(y: currentHeight - 44)

                NotchArrivalSweep(progress: arrivalSweep)
                    .frame(width: currentWidth, height: currentHeight)
            }
            .clipShape(shape)
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onAppear(perform: open)
        .onChange(of: presentation.isClosing) { _, closing in
            if closing { close() }
        }
    }

    /// The notch unfurls into the reading surface, a warm wash arrives at the lower edge, text follows.
    private func open() {
        if reduceMotion {
            expansion = 1
            contentVisible = true
            return
        }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) { expansion = 1 }
        withAnimation(.easeOut(duration: 0.28)) { arrivalGlow = 0.65 }
        withAnimation(.easeInOut(duration: 0.58).delay(0.10)) { arrivalSweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.easeOut(duration: 0.36)) { contentVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            withAnimation(.easeOut(duration: 0.55)) { arrivalGlow = 0 }
        }
    }

    /// Reverse: hide the text first, then shrink back into the notch.
    private func close() {
        withAnimation(.easeIn(duration: 0.15)) { contentVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.3)) { expansion = 0 }
        }
    }
}

/// The reply, spoken words bright and the rest dim, scrolling to keep up with the voice.
private struct TeleprompterText: View {
    @ObservedObject var activity: AgentVoiceActivity
    @State private var contentHeight: CGFloat = 0

    static let fontSize: CGFloat = 19
    static let lineSpacing: CGFloat = 5
    static let lineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return NSLayoutManager().defaultLineHeight(for: font) + lineSpacing
    }()

    var body: some View {
        GeometryReader { geometry in
            Text(attributedReply)
                .font(.system(size: Self.fontSize, weight: .semibold))
                .lineSpacing(Self.lineSpacing)
                .frame(width: geometry.size.width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { text in
                    Color.clear.preference(key: TeleprompterHeightKey.self, value: text.size.height)
                })
                .offset(y: -Self.offset(
                    spoken: activity.spokenCharacters, total: activity.replyText.count,
                    contentHeight: contentHeight, visibleHeight: geometry.size.height
                ))
                .animation(.easeInOut(duration: 0.4), value: Self.line(
                    spoken: activity.spokenCharacters, total: activity.replyText.count, contentHeight: contentHeight))
        }
        .clipped()
        .mask(
            LinearGradient(stops: [
                .init(color: .black.opacity(0.25), location: 0),
                .init(color: .black, location: 0.34),
                .init(color: .black, location: 0.66),
                .init(color: .black.opacity(0.25), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        )
        .onPreferenceChange(TeleprompterHeightKey.self) { contentHeight = $0 }
    }

    private var attributedReply: AttributedString {
        let text = activity.replyText
        let count = min(max(activity.spokenCharacters, 0), text.count)
        var said = AttributedString(String(text.prefix(count)))
        said.foregroundColor = .white.opacity(0.95)
        var ahead = AttributedString(String(text.dropFirst(count)))
        ahead.foregroundColor = .white.opacity(0.45)
        return said + ahead
    }

    /// The line being spoken, estimated from how far through the text the voice is.
    static func line(spoken: Int, total: Int, contentHeight: CGFloat) -> Int {
        guard total > 0, contentHeight > 0 else { return 0 }
        let lines = max(Int((contentHeight / lineHeight).rounded()), 1)
        let progress = Double(min(max(spoken, 0), total)) / Double(total)
        return min(Int(progress * Double(lines)), lines - 1)
    }

    /// Holds the spoken line in the middle row: the line before shows above it, the next one below.
    static func offset(spoken: Int, total: Int, contentHeight: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        let line = line(spoken: spoken, total: total, contentHeight: contentHeight)
        return CGFloat(line) * lineHeight - (visibleHeight - lineHeight) / 2
    }
}

/// What Claude is doing ("Reading ideas.md"), small, under the teleprompter, with the access level
/// on the right so it's always clear what she's allowed to do (Full in orange).
private struct AgentStepLine: View {
    @ObservedObject var activity: AgentVoiceActivity

    var body: some View {
        HStack(spacing: 8) {
            Text(activity.step)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.2), value: activity.step)
            if !activity.access.isEmpty {
                let tint: Color = activity.access == "Full" ? .orange : .white
                Text(activity.access)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
                    .fixedSize()
            }
        }
    }
}

private struct TeleprompterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
