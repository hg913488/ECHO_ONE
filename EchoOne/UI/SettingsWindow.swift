import SwiftUI
import AppKit
import CoreAudio
import ServiceManagement


final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(appState: AppState) {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(appState: appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Echo One Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = NSColor(red: 0.025, green: 0.048, blue: 0.068, alpha: 1.0)
        window.isOpaque = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 660)
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
final class SettingsDictationTestController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcript: String?
    @Published private(set) var lastError: String?

    private var recorder: AudioRecorder?
    private let transcriber: SpeechTranscriber

    init(transcriber: SpeechTranscriber) {
        self.transcriber = transcriber
    }

    func start() {
        guard !isRecording else { return }
        let recorder = AudioRecorder()
        recorder.targetDeviceID = AudioDeviceManager.selectedInputDeviceID()
        recorder.prewarm()

        do {
            try recorder.startRecording()
            self.recorder = recorder
            transcript = nil
            lastError = nil
            isRecording = true
        } catch {
            lastError = "Could not start recording."
        }
    }

    func stop() {
        guard isRecording, let recorder else { return }
        isRecording = false
        isTranscribing = true
        self.recorder = nil

        Task { @MainActor in
            let buffer = await recorder.stopRecording()
            let text = await transcriber.transcribe(audioBuffer: buffer)
            self.transcript = text
            self.lastError = text == nil ? "Echo One could not transcribe that sample." : nil
            self.isTranscribing = false
        }
    }
}

// MARK: - Settings View

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case cleanup
    case models
    case transcriptionLab
    case recognizedVoices
    case meetingTranscript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .cleanup: "Cleanup"
        case .models: "Models"
        case .transcriptionLab: "History"
        case .recognizedVoices: "Recognized Voices"
        case .meetingTranscript: "Meeting Transcript"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup behavior, shortcuts, microphone input, dictation testing, and sound feedback."
        case .cleanup: "Prompt cleanup, correction hints, OCR context, and learning behavior."
        case .models: "Speech and cleanup model downloads and runtime status."
        case .transcriptionLab: "Saved recordings, reruns, and cleanup experiments."
        case .recognizedVoices: "Reusable speaker labels and 'this is me' voice prints."
        case .meetingTranscript: "Auto-detect calls and transcribe meetings locally."
        }
    }

    var systemImageName: String {
        switch self {
        case .general: "gearshape"
        case .cleanup: "sparkles"
        case .models: "brain"
        case .transcriptionLab: "waveform.badge.magnifyingglass"
        case .recognizedVoices: "person.crop.circle.badge.checkmark"
        case .meetingTranscript: "waveform.badge.mic"
        }
    }

    var minimalIcon: String {
        switch self {
        case .general:           return "slider.horizontal.3"
        case .cleanup:           return "sparkles"
        case .models:            return "arrow.down.circle"
        case .transcriptionLab:  return "clock"
        case .recognizedVoices:  return "person"
        case .meetingTranscript: return "waveform"
        }
    }
}

struct RecordingSpeakerFilteringToggleState {
    let isVisible: Bool
    let isEnabled: Bool

    init(speechModel: SpeechModelDescriptor?) {
        isVisible = true
        isEnabled = speechModel?.supportsSpeakerFiltering ?? false
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var selectedDeviceID: AudioDeviceID = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hasScreenRecordingPermission = PermissionChecker.hasScreenRecordingPermission()
    @State private var hasAccessibilityPermission = PermissionChecker.checkAccessibility()
    @State private var hasInputMonitoringPermission = PermissionChecker.checkInputMonitoring()
    @State private var permissionPollTimer: Timer?
    @State private var selectedSection: SettingsSection = .general
    @State private var transcriptionLabPreviewSound: NSSound?
    @StateObject private var dictationTestController: SettingsDictationTestController
    @StateObject private var transcriptionLabController: TranscriptionLabController

    init(appState: AppState) {
        self.appState = appState
        _dictationTestController = StateObject(
            wrappedValue: SettingsDictationTestController(transcriber: appState.transcriber)
        )
        _transcriptionLabController = StateObject(
            wrappedValue: TranscriptionLabController(
                defaultSpeechModelID: appState.speechModel,
                defaultSpeakerTaggingEnabled: appState.ignoreOtherSpeakers,
                defaultCleanupModelKind: appState.textCleanupManager.selectedCleanupModelKind,
                loadStageTimings: {
                    try appState.loadTranscriptionLabStageTimings()
                },
                loadEntries: {
                    try appState.loadTranscriptionLabEntries()
                },
                audioURLForEntry: { entry in
                    appState.transcriptionLabAudioURL(for: entry)
                },
                runTranscription: { entry, speechModelID, speakerTaggingEnabled in
                    try await appState.rerunTranscriptionLabTranscription(
                        entry,
                        speechModelID: speechModelID,
                        speakerTaggingEnabled: speakerTaggingEnabled
                    )
                },
                runCleanup: { entry, rawTranscription, cleanupModelKind, prompt, includeWindowContext in
                    try await appState.rerunTranscriptionLabCleanup(
                        entry,
                        rawTranscription: rawTranscription,
                        cleanupModelKind: cleanupModelKind,
                        prompt: prompt,
                        includeWindowContext: includeWindowContext
                    )
                },
                loadSpeakerProfiles: { entryID in
                    try appState.loadTranscriptionLabSpeakerProfiles(for: entryID)
                },
                saveSpeakerProfile: { profile in
                    try appState.upsertTranscriptionLabSpeakerProfile(profile)
                },
                syncSelectedSpeechModelID: { speechModelID in
                    appState.speechModel = speechModelID
                    Task {
                        await appState.loadSpeechModel(name: speechModelID)
                    }
                },
                syncSpeakerTaggingEnabled: { speakerTaggingEnabled in
                    appState.ignoreOtherSpeakers = speakerTaggingEnabled
                },
                syncSelectedCleanupModelKind: { cleanupModelKind in
                    appState.textCleanupManager.selectedCleanupModelKind = cleanupModelKind
                    Task {
                        await appState.textCleanupManager.loadModel(kind: cleanupModelKind)
                    }
                }
            )
        )
    }

    private var modelRows: [RuntimeModelRow] {
        RuntimeModelInventory.rows(
            selectedSpeechModelName: appState.speechModel,
            activeSpeechModelName: appState.modelManager.modelName,
            speechModelState: appState.modelManager.state,
            speechDownloadProgress: appState.modelManager.downloadProgress,
            cachedSpeechModelNames: appState.modelManager.cachedModelNames,
            cleanupState: appState.textCleanupManager.state,
            selectedCleanupModelKind: appState.textCleanupManager.selectedCleanupModelKind,
            cachedCleanupKinds: appState.textCleanupManager.cachedModelKinds
        )
    }


    private var speakerFilteringToggleState: RecordingSpeakerFilteringToggleState {
        RecordingSpeakerFilteringToggleState(
            speechModel: SpeechModelCatalog.model(named: appState.speechModel)
        )
    }


    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sidebar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 8) {
                        Image("MenuBarIcon")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 15, height: 15)
                            .foregroundStyle(Color(red: 0.24, green: 0.83, blue: 0.70).opacity(0.85))
                        Text("Settings")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.80))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    ForEach(SettingsSection.allCases) { section in
                        SidebarNavRow(section: section, isSelected: selectedSection == section) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedSection = section
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 220, idealWidth: 220, maxWidth: 220, maxHeight: .infinity)
            .background(
                ZStack {
                    Color(red: 0.022, green: 0.042, blue: 0.060)
                    RadialGradient(
                        colors: [Color(red: 0.15, green: 0.55, blue: 0.55).opacity(0.13), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 280
                    )
                }
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)
            }

            // MARK: Content
            ScrollView {
                Group {
                    detailContent
                        .padding(.horizontal, 44)
                        .padding(.vertical, 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(selectedSection)
                .transition(.opacity)
            }
            .background(
                ZStack {
                    Color(red: 0.025, green: 0.048, blue: 0.068)
                    RadialGradient(
                        colors: [Color(red: 0.18, green: 0.65, blue: 0.60).opacity(0.14), .clear],
                        center: UnitPoint(x: 0.5, y: 0.55),
                        startRadius: 0,
                        endRadius: 480
                    )
                    RadialGradient(
                        colors: [Color(red: 0.12, green: 0.42, blue: 0.68).opacity(0.09), .clear],
                        center: UnitPoint(x: 0.25, y: 0.35),
                        startRadius: 0,
                        endRadius: 320
                    )
                    RadialGradient(
                        colors: [Color(red: 0.15, green: 0.62, blue: 0.48).opacity(0.08), .clear],
                        center: UnitPoint(x: 0.75, y: 0.72),
                        startRadius: 0,
                        endRadius: 280
                    )
                }
            )
        }
        .frame(minWidth: 880, minHeight: 660)
        .onAppear {
            inputDevices = AudioDeviceManager.listInputDevices()
            selectedDeviceID = AudioDeviceManager.selectedInputDeviceID() ?? AudioDeviceManager.defaultInputDeviceID() ?? 0
            refreshScreenRecordingPermission()
            refreshRequiredPermissions()
            startPermissionPollingIfNeeded()
            syncTranscriptionLabRerunDefaults()
            transcriptionLabController.reloadEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreenRecordingPermission()
            refreshRequiredPermissions()
        }
        .onChange(of: selectedSection) { _, newSection in
            if newSection == .transcriptionLab {
                syncTranscriptionLabRerunDefaults()
                transcriptionLabController.reloadEntries()
            }
        }
        .onChange(of: appState.speechModel) { _, _ in
            syncTranscriptionLabRerunDefaults()
        }
        .onChange(of: appState.textCleanupManager.selectedCleanupModelKind) { _, _ in
            syncTranscriptionLabRerunDefaults()
        }
        .onDisappear {
            if dictationTestController.isRecording {
                dictationTestController.stop()
            }
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
        }
    }

    private func refreshScreenRecordingPermission() {
        hasScreenRecordingPermission = PermissionChecker.hasScreenRecordingPermission()
    }

    private func downloadModel(_ row: RuntimeModelRow) {
        if row.id.hasPrefix("cleanup-") {
            if let kind = TextCleanupManager.cleanupModels.first(where: { "cleanup-\($0.fileName)" == row.id })?.kind {
                Task { await appState.textCleanupManager.loadModel(kind: kind) }
            }
        } else {
            // Select and load the requested model (triggers download if not cached)
            appState.speechModel = row.id
            Task { await appState.loadSpeechModel(name: row.id) }
        }
    }

    private func offloadModel(_ row: RuntimeModelRow) {
        if row.id.hasPrefix("cleanup-") {
            // Cleanup model
            if let kind = TextCleanupManager.cleanupModels.first(where: { "cleanup-\($0.fileName)" == row.id })?.kind {
                appState.textCleanupManager.deleteCachedModel(kind: kind)
            }
        } else {
            // Speech model
            if let model = SpeechModelCatalog.model(named: row.id) {
                appState.modelManager.deleteCachedModel(model)
            }
        }
    }

    private func refreshRequiredPermissions() {
        hasAccessibilityPermission = PermissionChecker.checkAccessibility()
        hasInputMonitoringPermission = PermissionChecker.checkInputMonitoring()
        if hasAccessibilityPermission && hasInputMonitoringPermission {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
        }
    }

    private func startPermissionPollingIfNeeded() {
        guard !hasAccessibilityPermission || !hasInputMonitoringPermission else { return }
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshRequiredPermissions()
        }
    }

    private func syncTranscriptionLabRerunDefaults() {
        transcriptionLabController.applyCurrentRerunDefaults(
            speechModelID: appState.speechModel,
            speakerTaggingEnabled: appState.ignoreOtherSpeakers,
            cleanupModelKind: appState.textCleanupManager.selectedCleanupModelKind
        )
    }

    private func playTranscriptionLabAudio(for entry: TranscriptionLabEntry) {
        let sound = NSSound(contentsOf: transcriptionLabController.audioURL(for: entry), byReference: false)
        transcriptionLabPreviewSound?.stop()
        transcriptionLabPreviewSound = sound
        transcriptionLabPreviewSound?.play()
    }

    private func copyTranscriptionLabTranscript(for entry: TranscriptionLabEntry) {
        let transcript = preferredTranscriptToCopy(for: entry)
        guard !transcript.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func preferredTranscriptToCopy(for entry: TranscriptionLabEntry) -> String {
        if let corrected = entry.correctedTranscription, !corrected.isEmpty {
            return corrected
        }

        return entry.rawTranscription ?? ""
    }


    private func formattedStageDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1000).rounded())) ms"
        }

        return String(format: "%.2f s", duration)
    }

    private func formattedOriginalStageDuration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "Not recorded"
        }

        return formattedStageDuration(duration)
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            if !(selectedSection == .transcriptionLab && transcriptionLabController.selectedEntry != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedSection.title)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    if selectedSection != .transcriptionLab {
                        Text(selectedSection.subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            switch selectedSection {
            case .general:
                generalSection
            case .cleanup:
                cleanupSection
            case .models:
                modelsSection
            case .transcriptionLab:
                transcriptionLabSection
            case .recognizedVoices:
                recognizedVoicesSection
            case .meetingTranscript:
                meetingTranscriptSection
            }

            Spacer(minLength: 0)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard("Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionStatusRow(
                        title: "Accessibility",
                        isGranted: hasAccessibilityPermission,
                        action: {
                            PermissionChecker.promptAccessibility()
                            PermissionChecker.openAccessibilitySettings()
                        }
                    )
                    PermissionStatusRow(
                        title: "Input Monitoring",
                        isGranted: hasInputMonitoringPermission,
                        action: {
                            PermissionChecker.promptInputMonitoring()
                            PermissionChecker.openInputMonitoringSettings()
                        }
                    )

                    if !hasAccessibilityPermission || !hasInputMonitoringPermission {
                        Text("Both permissions are required for hotkeys and pasting to work. If Echo One doesn't appear in Input Monitoring, click + and add it from Applications.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCard("Shortcuts") {
                VStack(alignment: .leading, spacing: 16) {
                    ShortcutRecorderView(
                        title: "Hold to Record",
                        chord: appState.pushToTalkChord,
                        onRecordingStateChange: appState.setShortcutCaptureActive
                    ) { chord in
                        appState.updateShortcut(chord, for: .pushToTalk)
                    }

                    ShortcutRecorderView(
                        title: "Toggle Recording",
                        chord: appState.toggleToTalkChord,
                        onRecordingStateChange: appState.setShortcutCaptureActive
                    ) { chord in
                        appState.updateShortcut(chord, for: .toggleToTalk)
                    }

                    Divider().opacity(0.15)

                    ShortcutRecorderView(
                        title: "Instruction Mode",
                        chord: appState.instructionModeChord,
                        onRecordingStateChange: appState.setShortcutCaptureActive
                    ) { chord in
                        appState.updateShortcut(chord, for: .instructionMode)
                    }

                    if let shortcutErrorMessage = appState.shortcutErrorMessage {
                        Text(shortcutErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Push to talk records while the hold chord stays down. Toggle starts and stops with the chord. Instruction mode holds to speak a command — select text first to transform it, or just speak to generate at cursor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard("Input") {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsField("Microphone") {
                        Picker("Microphone", selection: $selectedDeviceID) {
                            ForEach(inputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320, alignment: .leading)
                        .onChange(of: selectedDeviceID) { _, newValue in
                            AudioDeviceManager.setSelectedInputDevice(newValue)
                            appState.resetAudioEngine()
                        }
                    }

                    Toggle(
                        "Play sounds",
                        isOn: Binding(
                            get: { appState.playSounds },
                            set: { appState.playSounds = $0 }
                        )
                    )

                    Toggle(
                        "Pause media while recording",
                        isOn: $appState.pauseMediaWhileRecording
                    )

                    if speakerFilteringToggleState.isVisible {
                        Toggle(
                            "Ignore other speakers",
                            isOn: Binding(
                                get: { appState.ignoreOtherSpeakers },
                                set: { appState.ignoreOtherSpeakers = $0 }
                            )
                        )
                        .disabled(!speakerFilteringToggleState.isEnabled)
                    }
                }
            }

            SettingsCard("Test dictation") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Record a short sample with your current microphone and speech model without leaving Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(dictationTestController.isRecording ? "Stop test dictation" : "Start test dictation") {
                            if dictationTestController.isRecording {
                                dictationTestController.stop()
                            } else {
                                dictationTestController.start()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if dictationTestController.isRecording {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                Text("Recording…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if dictationTestController.isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Transcribing…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let transcript = dictationTestController.transcript {
                        Text(transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    } else if let lastError = dictationTestController.lastError {
                        Text(lastError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }

            SettingsCard("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
            }
        }
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard("Cleanup") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(
                        "Enable cleanup",
                        isOn: Binding(
                            get: { appState.cleanupEnabled },
                            set: { appState.setCleanupEnabled($0) }
                        )
                    )

                    if appState.cleanupEnabled {
                        if appState.textCleanupManager.state == .error {
                            Text(appState.textCleanupManager.errorMessage ?? "Error loading model")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Text("When enabled, Echo One runs local cleanup with the selected cleanup model from the Models section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard("Cleanup prompt") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Echo One uses this prompt before adding OCR context and correction hints.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    BorderedTextEditor(
                        text: $appState.cleanupPrompt,
                        minimumHeight: 140,
                        maximumHeight: 260,
                        monospaced: false
                    )

                    HStack {
                        Spacer()

                        Button("Reset to Default") {
                            appState.cleanupPrompt = TextCleaner.defaultPrompt
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsCard("Correction hints") {
                VStack(alignment: .leading, spacing: 20) {
                    CorrectionsEditor(
                        title: "Preferred transcriptions",
                        text: Binding(
                            get: { appState.correctionStore.preferredTranscriptionsText },
                            set: { appState.correctionStore.preferredTranscriptionsText = $0 }
                        ),
                        prompt: "One preferred word or phrase per line"
                    )

                    Divider()

                    CorrectionsEditor(
                        title: "Commonly misheard",
                        text: Binding(
                            get: { appState.correctionStore.commonlyMisheardText },
                            set: { appState.correctionStore.commonlyMisheardText = $0 }
                        ),
                        prompt: "One likely phrase pair per line using probably wrong -> probably right"
                    )

                    Text("Correction hints are added to the cleanup prompt; they are not applied as regexes or deterministic substitutions. Preferred transcriptions are also forwarded into OCR custom words.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard("Context") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(
                        "Use frontmost window OCR context",
                        isOn: Binding(
                            get: { appState.frontmostWindowContextEnabled },
                            set: { appState.frontmostWindowContextEnabled = $0 }
                        )
                    )

                    if appState.frontmostWindowContextEnabled && !hasScreenRecordingPermission {
                        ScreenRecordingRecoveryView {
                            _ = PermissionChecker.requestScreenRecordingPermission()
                            PermissionChecker.openScreenRecordingSettings()
                            refreshScreenRecordingPermission()
                        }
                    }

                    Toggle(
                        "Learn from manual corrections after paste",
                        isOn: Binding(
                            get: { appState.postPasteLearningEnabled },
                            set: { appState.postPasteLearningEnabled = $0 }
                        )
                    )

                    if appState.postPasteLearningEnabled && !hasScreenRecordingPermission {
                        ScreenRecordingRecoveryView {
                            _ = PermissionChecker.requestScreenRecordingPermission()
                            PermissionChecker.openScreenRecordingSettings()
                            refreshScreenRecordingPermission()
                        }
                    }

                    Text("Echo One uses high-quality OCR on the frontmost window and adds the result to the cleanup prompt. When learning is enabled, Echo One does a high-quality OCR check about 15 seconds after paste and only keeps narrow, high-confidence corrections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard("Speech model") {
                SettingsField("Active speech model") {
                    Picker("Speech Model", selection: $appState.speechModel) {
                        ForEach(ModelManager.availableModels) { model in
                            Text(model.pickerLabel).tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                    .onChange(of: appState.speechModel) { _, newModel in
                        Task {
                            await appState.loadSpeechModel(name: newModel)
                        }
                    }
                }

                Text("Echo One uses this model for speech recognition everywhere in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsField("Language") {
                    Picker("Language", selection: $appState.preferredLanguage) {
                        Text("Auto-detect").tag("auto")
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Portuguese").tag("pt")
                        Text("Italian").tag("it")
                        Text("Dutch").tag("nl")
                        Text("Chinese").tag("zh")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("Russian").tag("ru")
                        Text("Arabic").tag("ar")
                        Text("Hindi").tag("hi")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                }

                if appState.preferredLanguage != "auto" && appState.preferredLanguage != "en" && appState.speechModel.hasSuffix(".en") {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.white.opacity(0.9))
                            .font(.caption)
                        Text("You've selected a non-English language but are using an English-only model. Switch to **Multilingual** or **Parakeet v3** above for best results.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCard("Cleanup model") {
                SettingsField("Active cleanup model") {
                    Picker(
                        "Cleanup model",
                        selection: Binding(
                            get: { appState.textCleanupManager.selectedCleanupModelKind },
                            set: { appState.textCleanupManager.selectedCleanupModelKind = $0 }
                        )
                    ) {
                        ForEach(TextCleanupManager.cleanupModels, id: \.kind) { model in
                            Text(model.displayName).tag(model.kind)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360, alignment: .leading)
                    .onChange(of: appState.textCleanupManager.selectedCleanupModelKind) { _, _ in
                        Task {
                            await appState.textCleanupManager.loadModel()
                        }
                    }
                }

                Text("Recommended cleanup models are marked Very fast, Fast, and Full.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("Runtime models") {
                VStack(alignment: .leading, spacing: 16) {
                    ModelInventoryCard(rows: modelRows, onDelete: offloadModel, onDownload: downloadModel)

                    if let activeDownloadText = RuntimeModelInventory.activeDownloadText(rows: modelRows) {
                        Text(activeDownloadText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var transcriptionLabSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let selectedEntry = transcriptionLabController.selectedEntry {
                transcriptionLabDetail(for: selectedEntry)
            } else {
                Toggle(
                    "Save voice-to-text recordings to history",
                    isOn: $appState.transcriptionLabEnabled
                )

                if !appState.transcriptionLabEnabled {
                    Text("Voice-to-text history is off. Audio from dictation is not saved to disk. Meeting transcripts are saved separately as markdown files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                transcriptionLabBrowser
            }
        }
    }

    private var recognizedVoicesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ContentUnavailableView(
                "No Recognized Voices",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Run speaker tagging in History to create reusable voice prints.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    @State private var showClearHistoryConfirmation = false
    @State private var isTranscriptionStageExpanded = true
    @State private var isDiarizationStageExpanded = true
    @State private var isCleanupStageExpanded = true

    private var transcriptionLabBrowser: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent recordings")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !transcriptionLabController.entries.isEmpty {
                    Button("Clear History", role: .destructive) {
                        showClearHistoryConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .alert("Clear All History?", isPresented: $showClearHistoryConfirmation) {
                Button("Clear", role: .destructive) {
                    transcriptionLabController.deleteAllEntries(using: appState.transcriptionLabStore)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all saved recordings and transcriptions.")
            }

            TextField("Search transcriptions", text: $transcriptionLabController.searchText)
                .textFieldStyle(.roundedBorder)

            if transcriptionLabController.filteredEntries.isEmpty {
                if transcriptionLabController.searchText.isEmpty {
                    ContentUnavailableView(
                        "No Saved Recordings",
                        systemImage: "waveform",
                        description: Text("Make a few dictations in Echo One and they will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No transcriptions match \"\(transcriptionLabController.searchText)\".")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(transcriptionLabController.filteredEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                transcriptionLabController.selectEntry(entry.id)
                            } label: {
                                CompactTranscriptionLabEntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)

                            Button {
                                copyTranscriptionLabTranscript(for: entry)
                            } label: {
                                Image(systemName: "square.on.square")
                                    .font(.callout)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy this transcript")
                            .disabled(preferredTranscriptToCopy(for: entry).isEmpty)
                            .padding(.top, 12)

                            Button {
                                transcriptionLabController.deleteEntry(entry.id, using: appState.transcriptionLabStore)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this recording")
                            .padding(.top, 12)
                        }
                    }
                }
            }
        }
    }

    private func transcriptionLabDetail(for entry: TranscriptionLabEntry) -> some View {
        let canPlayRecording = transcriptionLabController.audioURL(for: entry).pathExtension.lowercased() == "wav"
        let originalSpeechModelName = SpeechModelCatalog.model(named: entry.speechModelID)?.pickerLabel ?? entry.speechModelID

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    transcriptionLabController.closeDetail()
                } label: {
                    Label("Back to recordings", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            TranscriptionLabWorkshopSummary(
                entry: entry,
                speechModelName: originalSpeechModelName,
                hasOriginalDiarization: transcriptionLabController.originalDiarizationVisualization != nil
            )
            TranscriptionLabSourceRecordingSummary(
                entry: entry,
                canPlayRecording: canPlayRecording
            ) {
                playTranscriptionLabAudio(for: entry)
            }
            transcriptionLabTranscriptionStage(for: entry, originalSpeechModelName: originalSpeechModelName)
            transcriptionLabDiarizationStage(for: entry, originalSpeechModelName: originalSpeechModelName)
            transcriptionLabCleanupStage(for: entry)

            if let errorMessage = transcriptionLabController.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private func transcriptionLabTranscriptionStage(
        for entry: TranscriptionLabEntry,
        originalSpeechModelName: String
    ) -> some View {
        TranscriptionLabStageDisclosure(
            "Transcription",
            isExpanded: $isTranscriptionStageExpanded
        ) {
            Text(originalSpeechModelName)
            Text(entry.rawTranscription?.isEmpty == false ? "Original available" : "No original text")
            Text(formattedOriginalStageDuration(transcriptionLabController.originalTranscriptionDuration))
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Original model and options")
                    .font(.subheadline.weight(.medium))
                Text("Originally transcribed with \(originalSpeechModelName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TranscriptionLabOutputComparison(
                originalTitle: "Original output",
                newTitle: "New output",
                hasNewOutput: !transcriptionLabController.experimentRawTranscription.isEmpty,
                placeholder: "Rerun transcription to compare a new transcript."
            ) {
                ReadOnlyTextPane(
                    text: entry.rawTranscription ?? "No transcription was captured for this recording.",
                    minimumHeight: 60,
                    maximumHeight: 140,
                    monospaced: false
                )
            } options: {
                HStack(alignment: .center, spacing: 12) {
                    Text("Rerun transcription options")
                        .font(.subheadline.weight(.medium))

                    Picker("Speech Model", selection: $transcriptionLabController.selectedSpeechModelID) {
                        ForEach(ModelManager.availableModels) { model in
                            Text(model.pickerLabel).tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300, alignment: .leading)

                    Spacer()
                }
            } action: {
                HStack(alignment: .center, spacing: 12) {
                    transcriptionLabRerunButton(
                        title: "Rerun transcription",
                        runningTitle: "Running...",
                        isRunning: transcriptionLabController.isRunningTranscription,
                        disabled: transcriptionLabController.runningStage != nil
                    ) {
                        Task {
                            await transcriptionLabController.rerunTranscription()
                        }
                    }

                    Spacer()

                    if let duration = transcriptionLabController.experimentTranscriptionDuration {
                        Text(formattedStageDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } newOutput: {
                DiffReadOnlyTextPane(
                    originalText: entry.rawTranscription ?? "",
                    text: transcriptionLabController.experimentRawTranscription,
                    minimumHeight: 60,
                    maximumHeight: 140,
                    monospaced: false
                )
            }
        }
    }

    private func transcriptionLabDiarizationStage(
        for entry: TranscriptionLabEntry,
        originalSpeechModelName: String
    ) -> some View {
        let selectedModelSupportsSpeakerTagging = SpeechModelCatalog.model(
            named: transcriptionLabController.selectedSpeechModelID
        )?.supportsSpeakerFiltering == true

        return TranscriptionLabStageDisclosure(
            "Diarization",
            isExpanded: $isDiarizationStageExpanded
        ) {
            Text(entry.speakerFilteringRan ? "Original tagged" : "Original off")
            Text(transcriptionLabController.originalDiarizationVisualization == nil ? "No timeline" : "Timeline available")
            Text(originalSpeechModelName)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Original model and options")
                    .font(.subheadline.weight(.medium))
                Text(entry.speakerFilteringRan
                     ? "Speaker tagging ran with \(originalSpeechModelName)."
                     : "Speaker tagging was off for the original transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TranscriptionLabOutputComparison(
                originalTitle: "Original timeline",
                newTitle: "New timeline",
                hasNewOutput: transcriptionLabController.experimentDiarizationVisualization != nil,
                placeholder: "Rerun speaker tagging to compare a new speaker timeline."
            ) {
                if let originalVisualization = transcriptionLabController.originalDiarizationVisualization {
                    TranscriptionLabDiarizationSummaryView(visualization: originalVisualization)
                } else {
                    Text("No original speaker tagging data was captured for this recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } options: {
                VStack(alignment: .leading, spacing: 12) {
                    transcriptionLabSpeakerIdentitiesSection

                    Text("Rerun speaker tagging options")
                        .font(.subheadline.weight(.medium))

                    HStack(alignment: .center, spacing: 12) {
                        Toggle(
                            "Run speaker tagging",
                            isOn: $transcriptionLabController.usesSpeakerTagging
                        )
                        .toggleStyle(.checkbox)
                        .disabled(!selectedModelSupportsSpeakerTagging || transcriptionLabController.runningStage != nil)

                        if !selectedModelSupportsSpeakerTagging {
                            Text("Speaker tagging is available only for FluidAudio models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            } action: {
                HStack(alignment: .center, spacing: 12) {
                    transcriptionLabRerunButton(
                        title: "Rerun speaker tagging",
                        runningTitle: "Running...",
                        isRunning: transcriptionLabController.isRunningTranscription,
                        disabled: transcriptionLabController.runningStage != nil || !selectedModelSupportsSpeakerTagging
                    ) {
                        Task {
                            await transcriptionLabController.rerunDiarization()
                        }
                    }

                    Spacer()

                    if let duration = transcriptionLabController.experimentTranscriptionDuration,
                       transcriptionLabController.experimentDiarizationVisualization != nil {
                        Text(formattedStageDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } newOutput: {
                if let experimentVisualization = transcriptionLabController.experimentDiarizationVisualization {
                    TranscriptionLabDiarizationSummaryView(visualization: experimentVisualization)

                    if let displayedSpeakerTaggedTranscriptText = transcriptionLabController.displayedSpeakerTaggedTranscriptText {
                        ReadOnlyTextPane(
                            text: displayedSpeakerTaggedTranscriptText,
                            minimumHeight: 84,
                            maximumHeight: 220,
                            monospaced: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptionLabSpeakerIdentitiesSection: some View {
        if transcriptionLabController.speakerProfilesInDisplayOrder.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text("Speaker identities")
                    .font(.subheadline.weight(.medium))

                ForEach(transcriptionLabController.speakerProfilesInDisplayOrder, id: \.speakerID) { profile in
                    TranscriptionLabSpeakerProfileEditor(
                        profile: profile,
                        effectiveDisplayName: transcriptionLabController.displayName(for: profile.speakerID) ?? profile.speakerID,
                        showsGlobalUpdateButton: false,
                        onDisplayNameChange: { updatedDisplayName in
                            transcriptionLabController.updateSpeakerDisplayName(
                                updatedDisplayName,
                                for: profile.speakerID
                            )
                        },
                        onIsMeChange: { isMe in
                            transcriptionLabController.setSpeakerIsMe(isMe, for: profile.speakerID)
                        },
                        onUpdateGlobalVoice: {
                            transcriptionLabController.pushSpeakerProfileToGlobalVoice(for: profile.speakerID)
                        }
                    )
                }
            }
        } else if transcriptionLabController.diarizationVisualization != nil {
            Text("Run speaker tagging again on this recording to attach editable speaker names and reusable voice prints.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func transcriptionLabCleanupStage(for entry: TranscriptionLabEntry) -> some View {
        TranscriptionLabStageDisclosure(
            "Cleanup",
            isExpanded: $isCleanupStageExpanded
        ) {
            Text(entry.cleanupModelName)
            Text(entry.correctedTranscription?.isEmpty == false ? "Original available" : "No original text")
            Text(formattedOriginalStageDuration(transcriptionLabController.originalCleanupDuration))
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Original model and options")
                    .font(.subheadline.weight(.medium))
                Text("Originally cleaned with \(entry.cleanupModelName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TranscriptionLabOutputComparison(
                originalTitle: "Original output",
                newTitle: "New output",
                hasNewOutput: !transcriptionLabController.experimentCorrectedTranscription.isEmpty,
                placeholder: "Rerun cleanup to compare a new cleanup output."
            ) {
                ReadOnlyTextPane(
                    text: entry.correctedTranscription ?? "No corrected output was captured for this recording.",
                    minimumHeight: 60,
                    maximumHeight: 140,
                    monospaced: false
                )
            } options: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rerun cleanup options")
                        .font(.subheadline.weight(.medium))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Cleanup prompt")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Reset to Default") {
                                appState.cleanupPrompt = TextCleaner.defaultPrompt
                            }
                            .buttonStyle(.bordered)
                            .disabled(transcriptionLabController.runningStage != nil)
                        }

                        BorderedTextEditor(
                            text: $appState.cleanupPrompt,
                            minimumHeight: 84,
                            maximumHeight: 132,
                            monospaced: false
                        )
                        .disabled(transcriptionLabController.runningStage != nil)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Toggle(
                            "Use captured OCR",
                            isOn: $transcriptionLabController.usesCapturedOCR
                        )
                        .toggleStyle(.checkbox)
                        .disabled(entry.windowContext == nil || transcriptionLabController.runningStage != nil)

                        Text("Clean with")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Cleanup model", selection: $transcriptionLabController.selectedCleanupModelKind) {
                            ForEach(TextCleanupManager.cleanupModels, id: \.kind) { model in
                                Text(model.displayName).tag(model.kind)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300, alignment: .leading)

                        Button("Show full cleanup transcript") {
                            if let transcript = transcriptionLabController.latestCleanupTranscript {
                                appState.showCleanupTranscript(transcript)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(transcriptionLabController.latestCleanupTranscript == nil)

                        Spacer()
                    }

                    DisclosureGroup("Correction hints") {
                        addCorrectionSection
                            .padding(.top, 8)
                    }

                    DisclosureGroup("Cleanup examples") {
                        addExampleSection(for: entry)
                            .padding(.top, 8)
                    }
                }
            } action: {
                HStack(alignment: .center, spacing: 12) {
                    transcriptionLabRerunButton(
                        title: "Rerun cleanup",
                        runningTitle: "Running...",
                        isRunning: transcriptionLabController.isRunningCleanup,
                        disabled: transcriptionLabController.runningStage != nil
                    ) {
                        Task {
                            await transcriptionLabController.rerunCleanup(prompt: appState.cleanupPrompt)
                        }
                    }

                    Spacer()

                    if let duration = transcriptionLabController.experimentCleanupDuration {
                        Text(formattedStageDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } newOutput: {
                DiffReadOnlyTextPane(
                    originalText: entry.correctedTranscription ?? "",
                    text: transcriptionLabController.experimentCorrectedTranscription,
                    minimumHeight: 60,
                    maximumHeight: 140,
                    monospaced: false
                )
            }
        }
    }

    private func transcriptionLabRerunButton(
        title: String,
        runningTitle: String,
        isRunning: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.trianglehead.clockwise")
                }
                Text(isRunning ? runningTitle : title)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }

    @State private var exampleInput: String = ""
    @State private var exampleOutput: String = ""
    @State private var exampleAdded: Bool = false
    @State private var correctionWrong: String = ""
    @State private var correctionRight: String = ""
    @State private var correctionAdded: Bool = false

    private var addCorrectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a word correction")
                .font(.subheadline.weight(.medium))

            Text("If a word is consistently misheard, add it here. Correction hints are added to the cleanup prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Misheard as:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. open claw", text: $correctionWrong)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Should be:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. OpenClaw", text: $correctionRight)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Button(action: {
                    guard !correctionWrong.isEmpty, !correctionRight.isEmpty else { return }
                    appState.correctionStore.appendCommonlyMisheard(
                        MisheardReplacement(wrong: correctionWrong, right: correctionRight)
                    )
                    correctionAdded = true
                    correctionWrong = ""
                    correctionRight = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { correctionAdded = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: correctionAdded ? "checkmark" : "plus.circle")
                        Text(correctionAdded ? "Added!" : "Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.9))
                .padding(.top, 16)
                .disabled(correctionWrong.isEmpty || correctionRight.isEmpty)
            }
        }
    }

    private func addExampleSection(for entry: TranscriptionLabEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an example to the cleanup prompt")
                .font(.subheadline.weight(.medium))

            Text("If the cleanup got it wrong, add an example so it handles similar cases correctly in the future.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Input (what was said):")
                    .font(.subheadline.weight(.medium))
                BorderedTextEditor(
                    text: $exampleInput,
                    minimumHeight: 50,
                    maximumHeight: 80,
                    monospaced: false
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Output (what it should be):")
                    .font(.subheadline.weight(.medium))
                BorderedTextEditor(
                    text: $exampleOutput,
                    minimumHeight: 50,
                    maximumHeight: 80,
                    monospaced: false
                )
            }

            HStack {
                Button(action: {
                    guard !exampleInput.isEmpty, !exampleOutput.isEmpty else { return }
                    let example = "\n\nInput: \"\(exampleInput)\"\nOutput: \(exampleOutput)\n"
                    if let range = appState.cleanupPrompt.range(of: "</EXAMPLES>") {
                        appState.cleanupPrompt.insert(contentsOf: example, at: range.lowerBound)
                    } else {
                        // No EXAMPLES block — append to end
                        appState.cleanupPrompt += "\n\n<EXAMPLES>\(example)</EXAMPLES>"
                    }
                    exampleAdded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exampleAdded = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: exampleAdded ? "checkmark" : "plus.circle")
                        Text(exampleAdded ? "Example added!" : "Add Example")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.9))
                .disabled(exampleInput.isEmpty || exampleOutput.isEmpty)

                Spacer()
            }
        }
        .onAppear {
            exampleInput = entry.rawTranscription ?? ""
            exampleOutput = entry.correctedTranscription ?? ""
            exampleAdded = false
        }
    }


    @ObservedObject private var calendarService = GoogleCalendarService.shared
    @State private var googleAuthCode = ""
    @State private var meetingDirectoryBookmark: URL? = {
        MeetingTranscriptSettings.loadSaveDirectory()
    }()

    private var meetingTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "flask")
                    .foregroundColor(Color.white.opacity(0.9))
                Text("Experimental")
                    .font(.caption.bold())
                    .foregroundColor(Color.white.opacity(0.9))
            }
            .padding(.horizontal, 4)

            SettingsCard("Meeting Transcription") {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle(
                        "Enable meeting transcription",
                        isOn: $appState.meetingTranscriptEnabled
                    )
                    .onChange(of: appState.meetingTranscriptEnabled) { _, _ in
                        appState.setupMeetingDetector()
                    }

                    Text("When enabled, Echo One can detect video calls and offer to transcribe them locally. Requires Screen Recording permission for system audio capture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appState.meetingTranscriptEnabled {
                        Toggle(
                            "Auto-detect meeting apps",
                            isOn: $appState.meetingAutoDetectEnabled
                        )
                        .onChange(of: appState.meetingAutoDetectEnabled) { _, _ in
                            appState.setupMeetingDetector()
                        }

                        Text("Monitors for Zoom, Teams, FaceTime, Meet, and other call apps. When detected, Echo One will ask if you'd like to transcribe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(
                            "Float the meeting window while recording",
                            isOn: $appState.meetingWindowFloatsWhileRecording
                        )
                        .onChange(of: appState.meetingWindowFloatsWhileRecording) { _, _ in
                            appState.refreshMeetingTranscriptWindowPresentation()
                        }

                        Text("Keeps the current meeting window above other windows only while an active meeting is recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if appState.meetingTranscriptEnabled {
                SettingsCard("Google Calendar") {
                    VStack(alignment: .leading, spacing: 12) {
                        if calendarService.isSignedIn {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connected to Google Calendar")
                                    .font(.body)
                                Spacer()
                                Button("Disconnect") {
                                    calendarService.signOut()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                            Text("Meeting titles and attendees will be auto-populated from your calendar when you start a recording.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if calendarService.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Connecting...")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Connect Google Calendar to automatically populate meeting titles and attendees when recording.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Connect Google Calendar") {
                                calendarService.signIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.white.opacity(0.9))
                        }
                    }
                }

                SettingsCard("Transcript Storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Save directory:")
                                .font(.body)

                            Text(meetingDirectoryBookmark?.path ?? MeetingTranscriptSettings.defaultSaveDirectory().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.canCreateDirectories = true
                                panel.message = "Choose where to save meeting transcripts"
                                panel.prompt = "Select Folder"

                                if panel.runModal() == .OK, let url = panel.url {
                                    MeetingTranscriptSettings.saveSaveDirectory(url)
                                    meetingDirectoryBookmark = url
                                }
                            }
                        }

                        Text("Transcripts are saved as Markdown files organized in date folders (e.g., 2026-04-07/standup.md).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard("Summary Prompt") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This prompt is used to generate a summary after a meeting ends. The transcript is sent to your local cleanup model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $appState.meetingSummaryPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 100)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

                        HStack {
                            Button("Reset to Default") {
                                appState.meetingSummaryPrompt = MeetingSummaryGenerator.finalSummaryPrompt
                            }
                            .font(.caption)
                        }
                    }
                }

                if !PermissionChecker.hasScreenRecordingPermission() {
                    SettingsCard("Permissions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Screen Recording permission is required to capture system audio (what other call participants say).")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Grant Screen Recording Permission") {
                                PermissionChecker.requestScreenRecordingPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.white.opacity(0.9))
                        }
                    }
                }
            }
        }
    }

}

private struct TranscriptionLabSpeakerProfileEditor: View {
    let profile: TranscriptionLabSpeakerProfile
    let effectiveDisplayName: String
    let showsGlobalUpdateButton: Bool
    let onDisplayNameChange: (String) -> Void
    let onIsMeChange: (Bool) -> Void
    let onUpdateGlobalVoice: () -> Void

    @State private var draftDisplayName: String
    @FocusState private var isNameFieldFocused: Bool

    init(
        profile: TranscriptionLabSpeakerProfile,
        effectiveDisplayName: String,
        showsGlobalUpdateButton: Bool,
        onDisplayNameChange: @escaping (String) -> Void,
        onIsMeChange: @escaping (Bool) -> Void,
        onUpdateGlobalVoice: @escaping () -> Void
    ) {
        self.profile = profile
        self.effectiveDisplayName = effectiveDisplayName
        self.showsGlobalUpdateButton = showsGlobalUpdateButton
        self.onDisplayNameChange = onDisplayNameChange
        self.onIsMeChange = onIsMeChange
        self.onUpdateGlobalVoice = onUpdateGlobalVoice
        _draftDisplayName = State(initialValue: profile.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(profile.speakerID)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .center, spacing: 12) {
                TextField(
                    "Name this speaker",
                    text: $draftDisplayName,
                    prompt: Text(effectiveDisplayName)
                )
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit(commitDisplayName)
                .onChange(of: isNameFieldFocused) { _, isFocused in
                    if !isFocused {
                        commitDisplayName()
                    }
                }

                Toggle(
                    "This is me",
                    isOn: Binding(
                        get: { profile.isMe },
                        set: onIsMeChange
                    )
                )
                .toggleStyle(.checkbox)
                .fixedSize()
            }

            if profile.evidenceTranscript.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tagged transcript evidence")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ReadOnlyTextPane(
                        text: profile.evidenceTranscript,
                        minimumHeight: 52,
                        maximumHeight: 110,
                        monospaced: false
                    )
                }
            }

            if showsGlobalUpdateButton {
                Button("Update global voice print") {
                    commitDisplayName()
                    onUpdateGlobalVoice()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onChange(of: profile.displayName) { _, newValue in
            if newValue != draftDisplayName {
                draftDisplayName = newValue
            }
        }
    }

    private func commitDisplayName() {
        guard draftDisplayName != profile.displayName else {
            return
        }

        onDisplayNameChange(draftDisplayName)
    }
}

private struct ScreenRecordingRecoveryView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Echo One needs Screen Recording access. Grant it in System Settings, then return to Echo One.")
                .font(.caption)
                .foregroundStyle(.red)

            Button("Open Screen Recording Settings", action: onOpenSettings)
            .controlSize(.small)
        }
    }
}

private struct SidebarNavRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    private let teal = Color(red: 0.24, green: 0.83, blue: 0.70)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.minimalIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? teal : Color.white.opacity(0.36))
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.90 : 0.50))

                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(teal.opacity(0.7))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? teal.opacity(0.10) : Color.clear)
                    .padding(.horizontal, 8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.35))
                .textCase(.uppercase)

            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.032))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
            content
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isGranted ? Color.green.opacity(0.85) : Color.red.opacity(0.75))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.82))
            Spacer()
            if !isGranted {
                Button("Grant Access") { action() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    )
            }
        }
    }
}

private struct CorrectionsEditor: View {
    let title: String
    let text: Binding<String>
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            BorderedTextEditor(text: text, minimumHeight: 96, maximumHeight: 160, monospaced: false)

            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct CompactTranscriptionLabEntryRow: View {
    let entry: TranscriptionLabEntry
    @State private var isHovered = false

    private var titleText: String {
        if let corrected = entry.correctedTranscription, !corrected.isEmpty {
            return corrected
        }

        if let raw = entry.rawTranscription, !raw.isEmpty {
            return raw
        }

        return "Recording without transcription"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.createdAt, style: .time)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(titleText)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 8) {
                Text(String(format: "%.1fs", entry.audioDuration))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DiffReadOnlyTextPane: View {
    let originalText: String
    let text: String
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let monospaced: Bool

    private var segments: [TranscriptionLabTextDiffSegment] {
        TranscriptionLabTextDiff.segments(from: originalText, to: text)
    }

    private var renderedText: String {
        TranscriptionLabTextDiff.renderedText(from: segments)
    }

    var body: some View {
        ScrollView {
            diffText
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(
            height: textPaneHeight(
                for: renderedText.isEmpty ? text : renderedText,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight
            )
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var diffText: Text {
        let font = monospaced ? Font.system(.body, design: .monospaced) : .body

        guard !segments.isEmpty else {
            return Text(text).font(font)
        }

        return segments.enumerated().reduce(Text("")) { result, item in
            let (index, segment) = item
            let prefix = index == 0 || !segment.needsLeadingSpace ? Text("") : Text(" ")
            return result + prefix + styledText(for: segment, font: font)
        }
    }

    private func styledText(for segment: TranscriptionLabTextDiffSegment, font: Font) -> Text {
        let base = Text(segment.text).font(font)

        switch segment.kind {
        case .unchanged:
            return base
        case .inserted:
            return base
                .foregroundColor(Color(nsColor: .systemGreen))
                .underline()
                .bold()
        case .removed:
            return base
                .foregroundColor(Color(nsColor: .systemRed))
                .strikethrough()
        }
    }
}

private struct BorderedTextEditor: View {
    let text: Binding<String>
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let monospaced: Bool

    var body: some View {
        TextEditor(text: text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .scrollContentBackground(.hidden)
            .frame(height: textPaneHeight(for: text.wrappedValue, minimumHeight: minimumHeight, maximumHeight: maximumHeight))
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

private func textPaneHeight(
    for text: String,
    minimumHeight: CGFloat,
    maximumHeight: CGFloat
) -> CGFloat {
    let lineCount = max(text.components(separatedBy: "\n").count, 1)
    let estimatedHeight = CGFloat(lineCount) * 20 + 28
    return min(max(estimatedHeight, minimumHeight), maximumHeight)
}

private struct TranscriptionLabWorkshopSummary: View {
    let entry: TranscriptionLabEntry
    let speechModelName: String
    let hasOriginalDiarization: Bool

    private var hasRawTranscription: Bool {
        entry.rawTranscription?.isEmpty == false
    }

    private var hasCleanedTranscription: Bool {
        entry.correctedTranscription?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    Text("Transcript workshop")
                        .font(.title3.weight(.semibold))

                    Spacer(minLength: 16)

                    statusPills
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Transcript workshop")
                        .font(.title3.weight(.semibold))

                    statusPills
                }
            }

            TranscriptionLabMetadataLine(items: [
                TranscriptionLabMetadataItem("Recorded", entry.createdAt.formatted(date: .abbreviated, time: .shortened)),
                TranscriptionLabMetadataItem("Duration", String(format: "%.1fs", entry.audioDuration)),
                TranscriptionLabMetadataItem("Speech", speechModelName),
                TranscriptionLabMetadataItem("Cleanup", entry.cleanupModelName),
            ])

            TranscriptionLabSettingsNotice()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var statusPills: some View {
        HStack(alignment: .center, spacing: 8) {
            TranscriptionLabStatusPill(
                title: "Transcribed",
                systemImage: "text.quote",
                tint: hasRawTranscription ? .green : .secondary
            )
            TranscriptionLabStatusPill(
                title: "Tagged",
                systemImage: "person.2.wave.2",
                tint: hasOriginalDiarization ? .green : .secondary
            )
            TranscriptionLabStatusPill(
                title: entry.cleanupUsedFallback ? "Cleanup fallback" : "Cleaned",
                systemImage: entry.cleanupUsedFallback ? "exclamationmark.triangle" : "sparkles",
                tint: hasCleanedTranscription && !entry.cleanupUsedFallback ? .green : Color.white.opacity(0.9)
            )
        }
    }
}

private struct TranscriptionLabMetadataItem: Identifiable {
    let label: String
    let value: String

    var id: String {
        "\(label)-\(value)"
    }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

private struct TranscriptionLabMetadataLine: View {
    let items: [TranscriptionLabMetadataItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                ForEach(items) { item in
                    metadataText(for: item)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(items) { item in
                    metadataText(for: item)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func metadataText(for item: TranscriptionLabMetadataItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(item.label)
                .fontWeight(.medium)
            Text(item.value)
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

private struct TranscriptionLabStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct TranscriptionLabSettingsNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("Changes you make here update app settings and become the defaults for future recordings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }
}

private struct TranscriptionLabSourceRecordingSummary: View {
    let entry: TranscriptionLabEntry
    let canPlayRecording: Bool
    let onPlay: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                sourceSummary
                Spacer(minLength: 16)
                playButton
            }

            VStack(alignment: .leading, spacing: 12) {
                sourceSummary
                playButton
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source recording")
                .font(.subheadline.weight(.semibold))

            TranscriptionLabMetadataLine(items: [
                TranscriptionLabMetadataItem("Recorded", entry.createdAt.formatted(date: .abbreviated, time: .shortened)),
                TranscriptionLabMetadataItem("Duration", String(format: "%.1fs", entry.audioDuration)),
                TranscriptionLabMetadataItem("Speech", SpeechModelCatalog.model(named: entry.speechModelID)?.statusName ?? entry.speechModelID),
                TranscriptionLabMetadataItem("Cleanup", entry.cleanupModelName),
            ])
        }
    }

    private var playButton: some View {
        Button {
            onPlay()
        } label: {
            Label("Play recording", systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .disabled(!canPlayRecording)
        .help(canPlayRecording ? "Play the saved recording" : "Playback is available for newly archived recordings")
    }
}

private struct TranscriptionLabStageDisclosure<SummaryContent: View, Content: View>: View {
    let title: String
    let summaryContent: SummaryContent
    let content: Content
    @Binding var isExpanded: Bool

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder summary: () -> SummaryContent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        summaryContent = summary()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptionLabStageHeaderButton(
                title: title,
                isExpanded: isExpanded,
                summary: summaryContent
            ) {
                isExpanded.toggle()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.top, 14)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct TranscriptionLabStageHeaderButton<SummaryContent: View>: View {
    let title: String
    let isExpanded: Bool
    let summary: SummaryContent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    summary
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TranscriptionLabOutputComparison<
    OriginalContent: View,
    OptionsContent: View,
    ActionContent: View,
    NewOutputContent: View
>: View {
    let originalTitle: String
    let newTitle: String
    let hasNewOutput: Bool
    let placeholder: String
    let originalContent: OriginalContent
    let optionsContent: OptionsContent
    let actionContent: ActionContent
    let newOutputContent: NewOutputContent

    init(
        originalTitle: String,
        newTitle: String,
        hasNewOutput: Bool,
        placeholder: String,
        @ViewBuilder original: () -> OriginalContent,
        @ViewBuilder options: () -> OptionsContent,
        @ViewBuilder action: () -> ActionContent,
        @ViewBuilder newOutput: () -> NewOutputContent
    ) {
        self.originalTitle = originalTitle
        self.newTitle = newTitle
        self.hasNewOutput = hasNewOutput
        self.placeholder = placeholder
        originalContent = original()
        optionsContent = options()
        actionContent = action()
        newOutputContent = newOutput()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(originalTitle)
                    .font(.subheadline.weight(.medium))
                originalContent
            }

            optionsContent

            actionContent

            VStack(alignment: .leading, spacing: 8) {
                Text(newTitle)
                    .font(.subheadline.weight(.medium))

                if hasNewOutput {
                    newOutputContent
                } else {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TranscriptionLabResultStack<SupplementaryContent: View>: View {
    let rawTitle: String
    let rawText: String
    let correctedTitle: String
    let correctedText: String
    let supplementaryContent: SupplementaryContent?

    init(
        rawTitle: String,
        rawText: String,
        correctedTitle: String,
        correctedText: String,
        @ViewBuilder supplementaryContent: () -> SupplementaryContent
    ) {
        self.rawTitle = rawTitle
        self.rawText = rawText
        self.correctedTitle = correctedTitle
        self.correctedText = correctedText
        self.supplementaryContent = supplementaryContent()
    }

    init(
        rawTitle: String,
        rawText: String,
        correctedTitle: String,
        correctedText: String
    ) where SupplementaryContent == EmptyView {
        self.rawTitle = rawTitle
        self.rawText = rawText
        self.correctedTitle = correctedTitle
        self.correctedText = correctedText
        self.supplementaryContent = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let supplementaryContent {
                supplementaryContent
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(rawTitle)
                    .font(.subheadline.weight(.medium))
                ReadOnlyTextPane(text: rawText, minimumHeight: 72, maximumHeight: 180, monospaced: false)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(correctedTitle)
                    .font(.subheadline.weight(.medium))
                ReadOnlyTextPane(text: correctedText, minimumHeight: 72, maximumHeight: 180, monospaced: false)
            }
        }
    }
}

private struct TranscriptionLabMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.callout)
        }
    }
}

private struct TranscriptionLabMetadataSummary: View {
    let entry: TranscriptionLabEntry

    var body: some View {
        HStack(spacing: 18) {
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            Text(String(format: "%.1fs", entry.audioDuration))
            Text(SpeechModelCatalog.model(named: entry.speechModelID)?.statusName ?? entry.speechModelID)
            Text(entry.cleanupModelName)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TranscriptionLabDiarizationSummaryView: View {
    private static let speakerPalette: [NSColor] = [
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPink,
        .systemTeal,
        .systemRed,
        .systemIndigo,
        .systemBrown,
    ]

    let visualization: TranscriptionLabController.DiarizationVisualization

    private var totalDuration: TimeInterval {
        max(
            visualization.audioDuration,
            visualization.spans.map(\.endTime).max() ?? 0
        )
    }

    private var summaryText: String {
        let speakerText = visualization.speakerIDsInDisplayOrder.isEmpty
            ? "Speaker tagging ran"
            : "Tagged \(formattedSpeakerCount(visualization.speakerIDsInDisplayOrder.count))"

        if visualization.usedFallback {
            if let fallbackReason = visualization.fallbackReason {
                return "\(speakerText), but transcription fell back to the full recording (\(fallbackReasonText(for: fallbackReason)))."
            }

            return "\(speakerText), but transcription fell back to the full recording."
        }

        if let targetSpeakerID = visualization.targetSpeakerID {
            if visualization.includedSpeakerIDsInDisplayOrder.count > 1 {
                return "\(speakerText) and transcribed \(formattedDuration(visualization.includedTranscriptDuration)) from \(includedSpeakerSummaryText(targetSpeakerID: targetSpeakerID))."
            }

            return "\(speakerText) and kept \(formattedDuration(visualization.keptAudioDuration)) from \(visualization.displayName(for: targetSpeakerID))."
        }

        return "\(speakerText)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("Speaker tagging")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(visualization.spans.enumerated()), id: \.offset) { _, span in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(speakerColor(for: span.speakerID))
                            .opacity(span.isIncludedInTranscript ? 1 : 0.32)
                            .frame(width: segmentWidth(for: span, totalWidth: geometry.size.width))
                            .overlay {
                                Text(span.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(span.isIncludedInTranscript ? Color.white : Color.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .padding(.horizontal, 6)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            if visualization.speakerIDsInDisplayOrder.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(visualization.speakerIDsInDisplayOrder, id: \.self) { speakerID in
                            HStack(alignment: .center, spacing: 6) {
                                Circle()
                                    .fill(speakerColor(for: speakerID))
                                    .frame(width: 8, height: 8)

                                Text(visualization.displayName(for: speakerID))

                                if let speakerStatus = speakerStatusText(for: speakerID) {
                                    Text(speakerStatus)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                if let targetSpeakerID = visualization.targetSpeakerID {
                    Text(
                        visualization.usedFallback
                            ? "Target: \(visualization.displayName(for: targetSpeakerID))"
                            : "Kept: \(visualization.displayName(for: targetSpeakerID))"
                    )
                }

                Text("Kept \(formattedDuration(visualization.keptAudioDuration))")

                if visualization.includedTranscriptDuration != visualization.keptAudioDuration {
                    Text("Transcript \(formattedDuration(visualization.includedTranscriptDuration))")
                }

                if visualization.usedFallback {
                    Text("Used full recording")
                }

                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func segmentWidth(
        for span: TranscriptionLabController.DiarizationVisualization.Span,
        totalWidth: CGFloat
    ) -> CGFloat {
        guard totalDuration > 0 else {
            return totalWidth / CGFloat(max(visualization.spans.count, 1))
        }

        return max(totalWidth * spanDurationFraction(for: span), 3)
    }

    private func spanDurationFraction(
        for span: TranscriptionLabController.DiarizationVisualization.Span
    ) -> CGFloat {
        CGFloat(max(0, span.endTime - span.startTime) / totalDuration)
    }

    private func speakerColor(for speakerID: String) -> Color {
        let speakerIDs = visualization.speakerIDsInDisplayOrder
        guard let speakerIndex = speakerIDs.firstIndex(of: speakerID) else {
            return Color.accentColor
        }

        let paletteIndex = speakerIndex % Self.speakerPalette.count
        return Color(nsColor: Self.speakerPalette[paletteIndex])
    }

    private func formattedSpeakerCount(_ count: Int) -> String {
        count == 1 ? "1 speaker" : "\(count) speakers"
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }

    private func includedSpeakerSummaryText(targetSpeakerID: String) -> String {
        let extraSpeakerCount = max(0, visualization.includedSpeakerIDsInDisplayOrder.count - 1)
        guard extraSpeakerCount > 0 else {
            return visualization.displayName(for: targetSpeakerID)
        }

        let extraText = extraSpeakerCount == 1
            ? "1 matching speaker"
            : "\(extraSpeakerCount) matching speakers"
        return "\(visualization.displayName(for: targetSpeakerID)) + \(extraText)"
    }

    private func speakerStatusText(for speakerID: String) -> String? {
        if visualization.usedFallback {
            return speakerID == visualization.targetSpeakerID ? "Target" : nil
        }

        if speakerID == visualization.targetSpeakerID {
            return "Kept"
        }

        return visualization.includedSpeakerIDsInDisplayOrder.contains(speakerID) ? "Included" : nil
    }

    private func fallbackReasonText(for reason: DiarizationSummary.FallbackReason) -> String {
        switch reason {
        case .noUsableSpeakerSpans:
            return "no usable speaker spans"
        case .noSpeakerReachedThreshold:
            return "no speaker reached the selection threshold"
        case .ambiguousDominantSpeaker:
            return "speaker split was too close to call"
        case .singleDetectedSpeaker:
            return "only one speaker was detected"
        case .insufficientKeptAudio:
            return "kept audio was too short"
        case .filteredAudioExtractionFailed:
            return "filtered audio extraction failed"
        case .emptyFilteredTranscription:
            return "filtered transcription came back empty"
        }
    }
}

private struct ReadOnlyTextPane: View {
    let text: String
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let monospaced: Bool

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: textPaneHeight(for: text, minimumHeight: minimumHeight, maximumHeight: maximumHeight))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct TranscriptionLabTextDiffSegment: Equatable {
    enum Kind: Equatable {
        case unchanged
        case inserted
        case removed
    }

    let kind: Kind
    let text: String

    fileprivate let needsLeadingSpace: Bool

    init(kind: Kind, text: String, needsLeadingSpace: Bool = false) {
        self.kind = kind
        self.text = text
        self.needsLeadingSpace = needsLeadingSpace
    }

    static func == (lhs: TranscriptionLabTextDiffSegment, rhs: TranscriptionLabTextDiffSegment) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text
    }
}

enum TranscriptionLabTextDiff {
    static func segments(from originalText: String, to newText: String) -> [TranscriptionLabTextDiffSegment] {
        let wordSegments = baseSegments(
            fromTokens: tokenize(originalText),
            toTokens: tokenize(newText),
            separator: " "
        )

        return refineSingleTokenReplacements(in: wordSegments)
    }

    static func renderedText(from segments: [TranscriptionLabTextDiffSegment]) -> String {
        segments.enumerated().reduce(into: "") { result, item in
            let (index, segment) = item
            if index > 0 && segment.needsLeadingSpace {
                result.append(" ")
            }
            result.append(segment.text)
        }
    }

    private static func baseSegments(
        fromTokens originalTokens: [String],
        toTokens newTokens: [String],
        separator: String,
        firstSegmentNeedsLeadingSpace: Bool = false
    ) -> [TranscriptionLabTextDiffSegment] {
        guard !originalTokens.isEmpty || !newTokens.isEmpty else {
            return []
        }

        var longestCommonSubsequence = Array(
            repeating: Array(repeating: 0, count: newTokens.count + 1),
            count: originalTokens.count + 1
        )

        for originalIndex in stride(from: originalTokens.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: newTokens.count - 1, through: 0, by: -1) {
                if originalTokens[originalIndex] == newTokens[newIndex] {
                    longestCommonSubsequence[originalIndex][newIndex] =
                        longestCommonSubsequence[originalIndex + 1][newIndex + 1] + 1
                } else {
                    longestCommonSubsequence[originalIndex][newIndex] = max(
                        longestCommonSubsequence[originalIndex + 1][newIndex],
                        longestCommonSubsequence[originalIndex][newIndex + 1]
                    )
                }
            }
        }

        var segments: [TranscriptionLabTextDiffSegment] = []
        var originalIndex = 0
        var newIndex = 0

        while originalIndex < originalTokens.count && newIndex < newTokens.count {
            if originalTokens[originalIndex] == newTokens[newIndex] {
                appendSegment(
                    kind: .unchanged,
                    token: originalTokens[originalIndex],
                    separator: separator,
                    firstSegmentNeedsLeadingSpace: firstSegmentNeedsLeadingSpace,
                    to: &segments
                )
                originalIndex += 1
                newIndex += 1
            } else if longestCommonSubsequence[originalIndex + 1][newIndex] >= longestCommonSubsequence[originalIndex][newIndex + 1] {
                appendSegment(
                    kind: .removed,
                    token: originalTokens[originalIndex],
                    separator: separator,
                    firstSegmentNeedsLeadingSpace: firstSegmentNeedsLeadingSpace,
                    to: &segments
                )
                originalIndex += 1
            } else {
                appendSegment(
                    kind: .inserted,
                    token: newTokens[newIndex],
                    separator: separator,
                    firstSegmentNeedsLeadingSpace: firstSegmentNeedsLeadingSpace,
                    to: &segments
                )
                newIndex += 1
            }
        }

        while originalIndex < originalTokens.count {
            appendSegment(
                kind: .removed,
                token: originalTokens[originalIndex],
                separator: separator,
                firstSegmentNeedsLeadingSpace: firstSegmentNeedsLeadingSpace,
                to: &segments
            )
            originalIndex += 1
        }

        while newIndex < newTokens.count {
            appendSegment(
                kind: .inserted,
                token: newTokens[newIndex],
                separator: separator,
                firstSegmentNeedsLeadingSpace: firstSegmentNeedsLeadingSpace,
                to: &segments
            )
            newIndex += 1
        }

        return segments
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func refineSingleTokenReplacements(
        in segments: [TranscriptionLabTextDiffSegment]
    ) -> [TranscriptionLabTextDiffSegment] {
        var refined: [TranscriptionLabTextDiffSegment] = []
        var index = 0

        while index < segments.count {
            if index + 1 < segments.count,
               segments[index].kind == .removed,
               segments[index + 1].kind == .inserted,
               !containsWhitespace(segments[index].text),
               !containsWhitespace(segments[index + 1].text) {
                let characterSegments = baseSegments(
                    fromTokens: segments[index].text.map { String($0) },
                    toTokens: segments[index + 1].text.map { String($0) },
                    separator: "",
                    firstSegmentNeedsLeadingSpace: segments[index].needsLeadingSpace
                )

                if characterSegments.contains(where: { $0.kind == .unchanged }) {
                    refined.append(contentsOf: characterSegments)
                    index += 2
                    continue
                }
            }

            refined.append(segments[index])
            index += 1
        }

        return refined
    }

    private static func containsWhitespace(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }

    private static func appendSegment(
        kind: TranscriptionLabTextDiffSegment.Kind,
        token: String,
        separator: String,
        firstSegmentNeedsLeadingSpace: Bool,
        to segments: inout [TranscriptionLabTextDiffSegment]
    ) {
        guard !token.isEmpty else {
            return
        }

        if let lastSegment = segments.last, lastSegment.kind == kind {
            segments[segments.count - 1] = TranscriptionLabTextDiffSegment(
                kind: kind,
                text: lastSegment.text + separator + token,
                needsLeadingSpace: lastSegment.needsLeadingSpace
            )
        } else {
            segments.append(
                .init(
                    kind: kind,
                    text: token,
                    needsLeadingSpace: segments.isEmpty ? firstSegmentNeedsLeadingSpace : !separator.isEmpty
                )
            )
        }
    }
}
