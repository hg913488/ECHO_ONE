import SwiftUI
import Combine
import CoreAudio
import ServiceManagement

enum AppStatus: String {
    case ready = "Ready"
    case loading = "Loading model..."
    case recording = "Recording..."
    case transcribing = "Transcribing..."
    case cleaningUp = "Cleaning up..."
    case error = "Error"
}

enum EmptyTranscriptionDisposition: Equatable {
    case cancel
    case showNoSoundDetected
}

@MainActor
class AppState: ObservableObject {
    enum PipelineOwner {
        case liveRecording
        case transcriptionLab
    }

    typealias CleanupResult = (
        text: String,
        prompt: String,
        attemptedCleanup: Bool,
        cleanupUsedFallback: Bool
    )
    typealias WindowContextProvider = @MainActor () async -> RecordingOCRPrefetchResult?

    private struct RecordingTranscriptionResult {
        let rawTranscription: String?
        let speakerFilteringRan: Bool
        let diarizationSummary: DiarizationSummary?
    }

    @Published var status: AppStatus = .loading
    @Published var isRecording: Bool = false
    @Published var liveTranscriptionPreview: String = ""
    @Published var errorMessage: String?
    @Published var shortcutErrorMessage: String?
    @Published var cleanupBackend: CleanupBackendOption {
        didSet {
            cleanupSettingsDefaults.set(cleanupBackend.rawValue, forKey: Self.cleanupBackendDefaultsKey)
        }
    }
    @Published var frontmostWindowContextEnabled: Bool {
        didSet {
            cleanupSettingsDefaults.set(
                frontmostWindowContextEnabled,
                forKey: Self.frontmostWindowContextEnabledDefaultsKey
            )
        }
    }
    @Published var playSounds: Bool {
        didSet {
            cleanupSettingsDefaults.set(
                playSounds,
                forKey: Self.playSoundsDefaultsKey
            )
        }
    }
    @AppStorage("cleanupEnabled") var cleanupEnabled: Bool = true
    @AppStorage("transcriptionLabEnabled") var transcriptionLabEnabled: Bool = false
    @AppStorage("cleanupPrompt") var cleanupPrompt: String = TextCleaner.defaultPrompt
    @AppStorage("speechModel") var speechModel: String = SpeechModelCatalog.defaultModelID
    @AppStorage("preferredLanguage") var preferredLanguage: String = "auto"
    @AppStorage(VoiceAgent.modelDefaultsKey) var voiceAgentModel: String = VoiceAgent.defaultModel
    /// Claude Code or Codex (Settings → Voice Agent → Agent).
    @AppStorage(VoiceAgent.providerDefaultsKey) var voiceAgentProvider: String = VoiceAgent.Provider.claude.rawValue
    /// Off: the Voice Agent shortcut does nothing (Settings → Voice Agent).
    @Published var voiceAgentEnabled: Bool = UserDefaults.standard.object(forKey: "voiceAgentEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(voiceAgentEnabled, forKey: "voiceAgentEnabled")
            if !voiceAgentEnabled { voiceAgent.stopSpeaking() }
            hotkeyMonitor.updateBindings(shortcutBindings)
        }
    }
    @AppStorage("meetingTranscriptEnabled") var meetingTranscriptEnabled: Bool = false
    @Published var showWhatsNew = false
    @AppStorage("meetingAutoDetectEnabled") var meetingAutoDetectEnabled: Bool = false
    @AppStorage("meetingWindowFloatsWhileRecording") var meetingWindowFloatsWhileRecording: Bool = true
    @AppStorage("openMeetingFolderOnEnd") var openMeetingFolderOnEnd: Bool = true
    @AppStorage("meetingSummariesEnabled") var meetingSummariesEnabled: Bool = true
    @AppStorage("formFillBetaEnabled") var formFillBetaEnabled: Bool = false
    @AppStorage("meetingSummaryPrompt") var meetingSummaryPrompt: String = MeetingSummaryGenerator.finalSummaryPrompt
    @AppStorage("pauseMediaWhileRecording") var pauseMediaWhileRecording: Bool = true
    @Published private(set) var pushToTalkChord: KeyChord
    @Published private(set) var toggleToTalkChord: KeyChord
    @Published private(set) var instructionModeChord: KeyChord
    @Published private(set) var voiceAgentChord: KeyChord
    @Published var postPasteLearningEnabled: Bool {
        didSet {
            cleanupSettingsDefaults.set(
                postPasteLearningEnabled,
                forKey: Self.postPasteLearningEnabledDefaultsKey
            )
            postPasteLearningCoordinator.learningEnabled = postPasteLearningEnabled
        }
    }
    @Published var ignoreOtherSpeakers: Bool {
        didSet {
            cleanupSettingsDefaults.set(
                ignoreOtherSpeakers,
                forKey: Self.ignoreOtherSpeakersDefaultsKey
            )
        }
    }

    let modelManager = ModelManager()
    let audioRecorder: AudioRecorder
    let transcriber: SpeechTranscriber
    let textPaster: TextPaster
    lazy var soundEffects = SoundEffects(isEnabled: { [weak self] in
        self?.playSounds ?? true
    })
    private lazy var mediaPlaybackController = MediaPlaybackController(enabled: { [weak self] in
        self?.pauseMediaWhileRecording ?? true
    })
    let hotkeyMonitor: HotkeyMonitoring
    let overlay = RecordingOverlayController()
    private let voiceAgent = VoiceAgent()
    let textCleanupManager: TextCleanupManager
    let frontmostWindowOCRService: FrontmostWindowOCRService
    let cleanupPromptBuilder: CleanupPromptBuilder
    let correctionStore: CorrectionStore
    let textCleaner: TextCleaner
    let chordBindingStore: ChordBindingStore
    let postPasteLearningCoordinator: PostPasteLearningCoordinator
    let transcriptionLabStore: TranscriptionLabStore
    let transcriptionLabSpeakerProfileStore: TranscriptionLabSpeakerProfileStore
    let appRelauncher: AppRelaunching
    var recordingSessionCoordinatorFactory: (() -> RecordingSessionCoordinator?)?
    var recordingTranscriptionSessionFactory: ((SpeechModelDescriptor) -> RecordingTranscriptionSession?)?
    var transcribeAudioBufferOverride: (([Float]) -> String?)?
    var cleanedTranscriptionResultOverride: ((String, OCRContext?) async -> CleanupResult)?
    private(set) var activeRecordingSessionCoordinator: RecordingSessionCoordinator?
    private(set) var activeRecordingTranscriptionSession: RecordingTranscriptionSession?

    var isReady: Bool {
        status == .ready
    }

    static func emptyTranscriptionDisposition(forAudioSampleCount sampleCount: Int) -> EmptyTranscriptionDisposition {
        if sampleCount < emptyTranscriptionCancelThresholdSampleCount {
            return .cancel
        }

        return .showNoSoundDetected
    }

    private var cleanupStateObserver: AnyCancellable?
    private var modelStateObserver: AnyCancellable?
    private let recordingOCRPrefetch: RecordingOCRPrefetch
    private var activeCleanupAttempted = false
    private var pipelineOwner: PipelineOwner?
    private let cleanupSettingsDefaults: UserDefaults
    private let inputMonitoringChecker: () -> Bool
    private let inputMonitoringPrompter: () -> Void
    private let selectedInputDeviceIDProvider: () -> AudioDeviceID?
    private let resetAudioRecorder: () -> Void
    private var hotkeyMonitorStarted = false
    private var pendingInstructionSelectedText: String?

    private enum ActiveRecordingMode {
        case dictation
        case instructionMode
        case voiceAgent
    }
    private var activeRecordingMode: ActiveRecordingMode = .dictation

    private static let instructionTransformPrompt = """
    You are a text transformation assistant. The user will provide selected text and a voice instruction. \
    Apply the instruction to the selected text. Return ONLY the transformed text — no explanations, \
    no preambles, no closing remarks.
    """

    private static let instructionGeneratePrompt = """
    You are a writing assistant. The user will provide a voice instruction. \
    Execute it and return ONLY the result — no explanations, no preambles, no closing remarks.
    """

    private static let cleanupBackendDefaultsKey = "cleanupBackend"
    private static let frontmostWindowContextEnabledDefaultsKey = "frontmostWindowContextEnabled"
    private static let postPasteLearningEnabledDefaultsKey = "postPasteLearningEnabled"
    private static let ignoreOtherSpeakersDefaultsKey = "ignoreOtherSpeakers"
    private static let playSoundsDefaultsKey = "playSounds"
    private static let archivedRecordingSampleRate = 16_000.0
    // History shows one decimal place, so shorter recordings render as 0.0s noise.
    private static let minimumArchivedRecordingSampleCount = 800
    private static let emptyTranscriptionCancelThresholdSampleCount = 8_000 // ~0.5 seconds — show "no sound" hint for almost all failed recordings
    private static let speechModelErrorPrefix = "Failed to load speech model: "
    static let liveRecordingNoInputErrorMessage = "Failed to start recording: No audio input device available."

    nonisolated static let defaultPushToTalkChord = KeyChord(keys: Set([
        PhysicalKey(keyCode: 54),  // Right Command
        PhysicalKey(keyCode: 61)   // Right Option
    ]))!

    nonisolated static let defaultToggleToTalkChord = KeyChord(keys: Set([
        PhysicalKey(keyCode: 54),  // Right Command
        PhysicalKey(keyCode: 61),  // Right Option
        PhysicalKey(keyCode: 49)   // Space
    ]))!

    nonisolated static let defaultInstructionModeChord = KeyChord(keys: Set([
        PhysicalKey(keyCode: 62)   // Right Control
    ]))!

    nonisolated static let defaultVoiceAgentChord = KeyChord(keys: Set([
        PhysicalKey(keyCode: 54),  // Right Command
        PhysicalKey(keyCode: 60)   // Right Shift
    ]))!

    nonisolated static let defaultShortcutBindings: [ChordAction: KeyChord] = [
        .pushToTalk: defaultPushToTalkChord,
        .toggleToTalk: defaultToggleToTalkChord,
        .instructionMode: defaultInstructionModeChord,
        .voiceAgent: defaultVoiceAgentChord
    ]

    init(
        hotkeyMonitor: HotkeyMonitoring = HotkeyMonitor(bindings: AppState.defaultShortcutBindings),
        chordBindingStore: ChordBindingStore = ChordBindingStore(),
        cleanupSettingsDefaults: UserDefaults = .standard,
        textCleanupManager: TextCleanupManager? = nil,
        frontmostWindowOCRService: FrontmostWindowOCRService = FrontmostWindowOCRService(),
        cleanupPromptBuilder: CleanupPromptBuilder = CleanupPromptBuilder(),
        correctionStore: CorrectionStore? = nil,
        audioRecorder: AudioRecorder = AudioRecorder(),
        textPaster: TextPaster = TextPaster(),
        transcriptionLabStore: TranscriptionLabStore = TranscriptionLabStore(),
        transcriptionLabSpeakerProfileStore: TranscriptionLabSpeakerProfileStore = TranscriptionLabSpeakerProfileStore(),
        appRelauncher: AppRelaunching? = nil,
        inputMonitoringChecker: @escaping () -> Bool = PermissionChecker.checkInputMonitoring,
        inputMonitoringPrompter: @escaping () -> Void = PermissionChecker.promptInputMonitoring,
        selectedInputDeviceIDProvider: @escaping () -> AudioDeviceID? = { AudioDeviceManager.selectedInputDeviceID() },
        resetAudioRecorder: (() -> Void)? = nil
    ) {
        self.hotkeyMonitor = hotkeyMonitor
        self.chordBindingStore = chordBindingStore
        self.cleanupSettingsDefaults = cleanupSettingsDefaults
        self.audioRecorder = audioRecorder
        self.textPaster = textPaster
        self.transcriptionLabStore = transcriptionLabStore
        self.transcriptionLabSpeakerProfileStore = transcriptionLabSpeakerProfileStore
        self.appRelauncher = appRelauncher ?? AppRelauncher()
        self.inputMonitoringChecker = inputMonitoringChecker
        self.inputMonitoringPrompter = inputMonitoringPrompter
        self.selectedInputDeviceIDProvider = selectedInputDeviceIDProvider
        self.resetAudioRecorder = resetAudioRecorder ?? { [audioRecorder] in
            audioRecorder.resetForDeviceChange()
        }
        self.pushToTalkChord = chordBindingStore.binding(for: .pushToTalk) ?? AppState.defaultPushToTalkChord
        self.toggleToTalkChord = chordBindingStore.binding(for: .toggleToTalk) ?? AppState.defaultToggleToTalkChord
        self.instructionModeChord = chordBindingStore.binding(for: .instructionMode) ?? AppState.defaultInstructionModeChord
        self.voiceAgentChord = chordBindingStore.binding(for: .voiceAgent) ?? AppState.defaultVoiceAgentChord
        self.textCleanupManager = textCleanupManager ?? TextCleanupManager(defaults: cleanupSettingsDefaults)
        self.frontmostWindowOCRService = frontmostWindowOCRService
        self.recordingOCRPrefetch = RecordingOCRPrefetch { [frontmostWindowOCRService] customWords in
            await frontmostWindowOCRService.captureContext(customWords: customWords)
        }
        self.cleanupPromptBuilder = cleanupPromptBuilder
        self.correctionStore = correctionStore ?? CorrectionStore(defaults: cleanupSettingsDefaults)
        let storedCleanupBackend = CleanupBackendOption(
            rawValue: cleanupSettingsDefaults.string(forKey: Self.cleanupBackendDefaultsKey) ?? ""
        ) ?? .localModels
        let storedFrontmostWindowContextEnabled = cleanupSettingsDefaults.bool(
            forKey: Self.frontmostWindowContextEnabledDefaultsKey
        )
        let storedPostPasteLearningEnabled: Bool
        if cleanupSettingsDefaults.object(forKey: Self.postPasteLearningEnabledDefaultsKey) == nil {
            storedPostPasteLearningEnabled = true
        } else {
            storedPostPasteLearningEnabled = cleanupSettingsDefaults.bool(
                forKey: Self.postPasteLearningEnabledDefaultsKey
            )
        }
        let storedIgnoreOtherSpeakers: Bool
        if cleanupSettingsDefaults.object(forKey: Self.ignoreOtherSpeakersDefaultsKey) == nil {
            storedIgnoreOtherSpeakers = false
        } else {
            storedIgnoreOtherSpeakers = cleanupSettingsDefaults.bool(
                forKey: Self.ignoreOtherSpeakersDefaultsKey
            )
        }
        self.cleanupBackend = storedCleanupBackend
        self.frontmostWindowContextEnabled = storedFrontmostWindowContextEnabled
        self.postPasteLearningEnabled = storedPostPasteLearningEnabled
        self.ignoreOtherSpeakers = storedIgnoreOtherSpeakers
        if cleanupSettingsDefaults.object(forKey: Self.playSoundsDefaultsKey) == nil {
            self.playSounds = true
        } else {
            self.playSounds = cleanupSettingsDefaults.bool(forKey: Self.playSoundsDefaultsKey)
        }
        // One-time migration: enable meeting transcription for existing users on update
        if UserDefaults.standard.object(forKey: "meetingTranscriptEnabled") == nil,
           UserDefaults.standard.object(forKey: "selectedCleanupModelKind") != nil {
            // User has used the app before (has a cleanup model selected) but never saw
            // the meeting transcript setting → this is an update, enable it
            meetingTranscriptEnabled = true
        }
        // Show "What's New" dialog once after update introduces meetings
        if !UserDefaults.standard.bool(forKey: "hasSeenMeetingTranscriptAnnouncement"),
           UserDefaults.standard.object(forKey: "selectedCleanupModelKind") != nil {
            showWhatsNew = true
        }
        self.transcriber = SpeechTranscriber(modelManager: modelManager)
        self.textCleaner = TextCleaner(
            cleanupManager: self.textCleanupManager,
            correctionStore: self.correctionStore
        )
        self.postPasteLearningCoordinator = PostPasteLearningCoordinator(
            correctionStore: self.correctionStore,
            learningEnabled: storedPostPasteLearningEnabled,
            revisit: { session in
                await PostPasteLearningObservationProvider.captureObservation(
                    for: session
                )
            }
        )

        // Forward nested model manager state changes so SwiftUI refreshes settings rows in place.
        // A stored model the catalog no longer offers (e.g. Qwen3-ASR) falls back to the default.
        if SpeechModelCatalog.model(named: speechModel) == nil {
            speechModel = SpeechModelCatalog.defaultModelID
        }
        // Parakeet only covers European languages, so a language only Whisper handled goes back to Auto.
        if ["zh", "ja", "ko", "ar", "hi"].contains(preferredLanguage) {
            preferredLanguage = "auto"
        }
        modelManager.customVocabularyProvider = { [correctionStore = self.correctionStore] in
            correctionStore.preferredTranscriptions
        }
        modelStateObserver = self.modelManager.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }

        // Forward cleanup manager state changes to trigger menu bar icon refresh.
        cleanupStateObserver = self.textCleanupManager.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }

        cleanupSettingsDefaults.set(storedCleanupBackend.rawValue, forKey: Self.cleanupBackendDefaultsKey)
        cleanupSettingsDefaults.set(
            storedFrontmostWindowContextEnabled,
            forKey: Self.frontmostWindowContextEnabledDefaultsKey
        )
        cleanupSettingsDefaults.set(
            storedPostPasteLearningEnabled,
            forKey: Self.postPasteLearningEnabledDefaultsKey
        )
        cleanupSettingsDefaults.set(
            storedIgnoreOtherSpeakers,
            forKey: Self.ignoreOtherSpeakersDefaultsKey
        )
        cleanupSettingsDefaults.set(
            playSounds,
            forKey: Self.playSoundsDefaultsKey
        )
        persistShortcutBindingsIfNeeded()
        hotkeyMonitor.updateBindings(shortcutBindings)
        self.textPaster.onPaste = { [postPasteLearningCoordinator = self.postPasteLearningCoordinator] session in
            postPasteLearningCoordinator.handlePaste(session)
        }
        self.postPasteLearningCoordinator.onLearnedCorrection = { [weak overlay] replacement in
            Task { @MainActor in
                overlay?.show(message: .learnedCorrection(replacement))
            }
        }
    }

    func initialize(skipPermissionPrompts: Bool = false) async {
        // Enable launch at login by default on first run
        if !UserDefaults.standard.bool(forKey: "hasSetLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "hasSetLaunchAtLogin")
            try? SMAppService.mainApp.register()
        }

        if !skipPermissionPrompts {
            let hasMic = await PermissionChecker.checkMicrophone()
            if !hasMic {
                errorMessage = "Microphone access required"
                status = .error
                return
            }

            let needsAccessibility = !PermissionChecker.checkAccessibility()
            let needsInputMonitoring = !inputMonitoringChecker()
            if needsAccessibility || needsInputMonitoring {
                showSettings()
            }
        }

        // Show "What's New" dialog for returning users who haven't seen the meeting announcement
        if showWhatsNew {
            showWhatsNew = false
            UserDefaults.standard.set(true, forKey: "hasSeenMeetingTranscriptAnnouncement")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "What's New in Echo One"
                alert.informativeText = "Meeting transcription is here — record calls with notes, transcript, and AI-generated summaries.\n\n100% local. 100% private. Nothing leaves your Mac."
                alert.alertStyle = .informational
                alert.icon = NSImage(named: "AppIcon")
                alert.addButton(withTitle: "Open Meetings")
                alert.addButton(withTitle: "Got It")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    showMeetingTranscriptWindow()
                }
            }
        }

        // Wire up "no sound" overlay to open settings
        overlay.onNoSoundSettingsTapped = { [weak self] in
            self?.showSettings()
        }

        // Pre-warm audio engine so first recording starts faster
        audioRecorder.prewarm()
        FocusedElementLocator.startPasteTargetTracking()

        status = .loading
        let showOverlay = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if showOverlay {
            overlay.show(message: .modelLoading)
        }
        if !modelManager.isReady {
            await loadSpeechModel(name: speechModel)
        }
        if showOverlay {
            overlay.dismiss()
        }

        guard modelManager.isReady else {
            return
        }

        await startHotkeyMonitor()

        await refreshCleanupModelState()

        // Start meeting detection if enabled
        setupMeetingDetector()
    }

    func relaunchApp() {
        do {
            try appRelauncher.relaunch()
        } catch {
            errorMessage = "Failed to relaunch Echo One: \(error.localizedDescription)"
        }
    }

    func startHotkeyMonitor() async {
        hotkeyMonitor.onRecordingStart = nil
        hotkeyMonitor.onRecordingStop = nil
        hotkeyMonitor.onRecordingRestart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Push-to-talk upgraded to toggle — reset buffer only if recording just started
                // (less than 1 second of audio at 16kHz). If they've been talking longer, keep it.
                let sampleCount = self.audioRecorder.audioBuffer.count
                if sampleCount < 16000 {
                    self.audioRecorder.resetBuffer()
                }
            }
        }

        hotkeyMonitor.onPushToTalkStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }
        hotkeyMonitor.onPushToTalkStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }
        hotkeyMonitor.onToggleToTalkStart = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }
        hotkeyMonitor.onToggleToTalkStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }
        hotkeyMonitor.onInstructionModeStart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pendingInstructionSelectedText = FocusedElementLocator().selectedText()
                self.activeRecordingMode = .instructionMode
                await self.startRecording()
            }
        }
        hotkeyMonitor.onInstructionModeStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }
        // Someone who uses the Voice Agent gets the voice loaded now, so the first reply after launch isn't silent
        // while it prepares (~15 s the first time after an install, ~3 s after that).
        if voiceAgentEnabled, !AgentTranscriptLog.days().isEmpty {
            voiceAgent.warmUpVoice()
        }
        hotkeyMonitor.onVoiceAgentStart = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // The first press shows the Voice Agent notice instead of listening; after "I Understand"
                // the next press talks. The key release finds nothing recording and does nothing.
                guard self.voiceAgentTermsAccepted() else { return }
                self.activeRecordingMode = .voiceAgent
                self.voiceAgent.warmUpVoice()
                self.voiceAgent.prepareClaude()
                self.voiceAgent.stopSpeaking()
                let activity = self.voiceAgent.activity
                activity.reset()
                self.overlay.attachVoiceActivity(activity)
                // The orb pulses with the mic while HG talks.
                self.audioRecorder.onLevel = { [weak activity] level in
                    DispatchQueue.main.async { activity?.level = level }
                }
                await self.startRecording()
            }
        }
        hotkeyMonitor.onVoiceAgentStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        hotkeyMonitor.updateBindings(shortcutBindings)

        if hotkeyMonitorStarted {
            if status != .error {
                status = .ready
                errorMessage = nil
            }
            return
        }

        if !inputMonitoringChecker() {
            // Try to prompt, but don't block — Accessibility alone may be sufficient
            inputMonitoringPrompter()
        }

        if hotkeyMonitor.start() {
            hotkeyMonitorStarted = true
            startEscapeMonitor()
            status = .ready
            errorMessage = nil
        } else {
            PermissionChecker.promptAccessibility()
            errorMessage = "Accessibility access required — grant permission then click Retry"
            status = .error
        }
    }

    func prepareRecordingSessionIfNeeded() async {
        audioRecorder.onConvertedAudioChunk = nil
        activeRecordingSessionCoordinator = nil
        activeRecordingTranscriptionSession = nil

        if let speechModelDescriptor = SpeechModelCatalog.model(named: speechModel) {
            if let recordingTranscriptionSessionFactory {
                activeRecordingTranscriptionSession = recordingTranscriptionSessionFactory(
                    speechModelDescriptor
                )
            } else if let recordingTranscriptionSession = modelManager.makeRecordingTranscriptionSession() {
                activeRecordingTranscriptionSession = recordingTranscriptionSession
            } else if speechModelDescriptor.backend == .fluidAudio {
                activeRecordingTranscriptionSession = ChunkedRecordingTranscriptionSession(
                    transcribeChunk: { [weak self] samples in
                        await self?.transcribeAudioBuffer(samples)
                    }
                )
            }
            if let session = activeRecordingTranscriptionSession as? ChunkedRecordingTranscriptionSession {
                session.onSegmentTranscribed = { [weak self] text in
                    DispatchQueue.main.async { self?.appendLiveTranscriptionChunk(text) }
                }
            }
        }

        guard ignoreOtherSpeakers, selectedSpeechModelSupportsSpeakerFiltering else {
            if let activeRecordingTranscriptionSession {
                audioRecorder.onConvertedAudioChunk = { [weak activeRecordingTranscriptionSession] samples in
                    activeRecordingTranscriptionSession?.appendAudioChunk(samples)
                }
            }
            return
        }

        let coordinator: RecordingSessionCoordinator?
        if let recordingSessionCoordinatorFactory {
            coordinator = recordingSessionCoordinatorFactory()
        } else {
            coordinator = await modelManager.makeRecordingSessionCoordinator()
        }

        guard let coordinator else {
            if let activeRecordingTranscriptionSession {
                audioRecorder.onConvertedAudioChunk = { [weak activeRecordingTranscriptionSession] samples in
                    activeRecordingTranscriptionSession?.appendAudioChunk(samples)
                }
            }
            return
        }

        activeRecordingSessionCoordinator = coordinator
        audioRecorder.onConvertedAudioChunk = {
            [weak coordinator, weak activeRecordingTranscriptionSession] samples in
            coordinator?.appendAudioChunk(samples)
            activeRecordingTranscriptionSession?.appendAudioChunk(samples)
        }
    }

    private func clearRecordingSessionCoordinator() {
        audioRecorder.onConvertedAudioChunk = nil
        activeRecordingSessionCoordinator = nil
        activeRecordingTranscriptionSession = nil
    }

    private var selectedSpeechModelSupportsSpeakerFiltering: Bool {
        SpeechModelCatalog.model(named: speechModel)?.supportsSpeakerFiltering == true
    }

    private func startRecording() async {
        // If the selected speech model isn't ready, show loading message
        guard status == .ready else {
            if status == .loading {
                overlay.show(message: .modelLoading)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.overlay.dismiss()
                }
            }
            return
        }

        guard acquirePipeline(for: .liveRecording) else {
            activeCleanupAttempted = false
            return
        }
        voiceAgent.stopSpeaking()

        do {
            // Start audio capture FIRST so the engine begins recording immediately and
            // no leading audio is clipped. Session/diarization setup (which can spin up a
            // coordinator model) then runs after capture is already live — it only feeds
            // the live preview; the final transcript uses the full buffer regardless.
            audioRecorder.onConvertedAudioChunk = nil
            mediaPlaybackController.pauseIfPlaying()
            audioRecorder.targetDeviceID = selectedInputDeviceIDProvider()
            try audioRecorder.startRecording()

            await prepareRecordingSessionIfNeeded()
            if cleanupEnabled && canAttemptCleanup && frontmostWindowContextEnabled {
                recordingOCRPrefetch.start(customWords: ocrCustomWords)
            } else {
                recordingOCRPrefetch.cancel()
            }
            if cleanupEnabled && canAttemptCleanup {
                let promptComponents = activeCleanupPromptComponents(windowContext: nil)
                textCleanupManager.startPromptPrefill(
                    systemPromptPrefix: promptComponents.stablePromptPrefix,
                    modelKind: textCleanupManager.selectedCleanupModelKind
                )
            } else {
                textCleanupManager.cancelPromptPrefill()
            }
            soundEffects.playStart()
            liveTranscriptionPreview = ""
            overlay.onStopTapped = { [weak self] in self?.stopRecordingIfActive() }
            switch activeRecordingMode {
            case .instructionMode: overlay.show(message: .instructionRecording)
            case .voiceAgent: overlay.show(message: .agentRecording)
            case .dictation:
                // The dictation mark's bars move with the mic.
                let level = overlay.dictationLevel
                level.value = 0
                audioRecorder.onLevel = { value in
                    DispatchQueue.main.async { level.value = value }
                }
                overlay.show(message: .recording)
            }
            isRecording = true
            status = .recording
        } catch {
            recordingOCRPrefetch.cancel()
            releasePipeline(owner: .liveRecording)
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            status = .error
        }
    }

    private var isTranscribing = false

    func stopRecordingIfActive() {
        Task { @MainActor in await stopRecordingAndTranscribe() }
    }

    func appendLiveTranscriptionChunk(_ text: String) {
        guard !text.isEmpty else { return }
        if liveTranscriptionPreview.isEmpty {
            liveTranscriptionPreview = text
        } else {
            liveTranscriptionPreview += " " + text
        }
        overlay.updateLiveText(liveTranscriptionPreview)
    }

    private func stopRecordingAndTranscribe() async {
        guard status == .recording, !isTranscribing else { return }
        isTranscribing = true
        defer { isTranscribing = false }

        let mode = activeRecordingMode
        activeRecordingMode = .dictation

        let buffer = await audioRecorder.stopRecording()
        let recordingSessionCoordinator = activeRecordingSessionCoordinator
        let recordingTranscriptionSession = activeRecordingTranscriptionSession
        clearRecordingSessionCoordinator()
        soundEffects.playStop()
        mediaPlaybackController.resumeIfPaused()
        isRecording = false
        status = .transcribing
        audioRecorder.onLevel = nil
        overlay.dictationLevel.value = 0
        if mode == .voiceAgent {
            voiceAgent.activity.level = 0
            overlay.show(message: .agentThinking)
        } else {
            overlay.show(message: .transcribing)
        }

        if mode == .instructionMode {
            let selectedText = pendingInstructionSelectedText
            pendingInstructionSelectedText = nil
            let rawTranscript = await transcribedTextForRecording(
                buffer,
                recordingSessionCoordinator: recordingSessionCoordinator,
                recordingTranscriptionSession: recordingTranscriptionSession
            ).rawTranscription

            overlay.dismiss(ifShowing: .transcribing)

            if let rawTranscript {
                await processInstructionResult(transcript: rawTranscript, selectedText: selectedText)
            } else {
                switch Self.emptyTranscriptionDisposition(forAudioSampleCount: buffer.count) {
                case .cancel:
                    overlay.dismiss()
                case .showNoSoundDetected:
                    overlay.show(message: .noSoundDetected)
                }
            }

            status = .ready
            releasePipeline(owner: .liveRecording)
            return
        }

        if mode == .voiceAgent {
            let rawTranscript = await transcribedTextForRecording(
                buffer,
                recordingSessionCoordinator: recordingSessionCoordinator,
                recordingTranscriptionSession: recordingTranscriptionSession
            ).rawTranscription

            overlay.dismiss(ifShowing: .transcribing)
            // Free the pipeline before waiting on Claude so dictation keeps working meanwhile.
            status = .ready
            releasePipeline(owner: .liveRecording)

            if let rawTranscript {
                await processAgentCommand(rawTranscript)
            } else {
                switch Self.emptyTranscriptionDisposition(forAudioSampleCount: buffer.count) {
                case .cancel:
                    overlay.dismiss()
                case .showNoSoundDetected:
                    overlay.show(message: .noSoundDetected)
                }
            }
            return
        }

        let windowContextProvider: WindowContextProvider?
        if frontmostWindowContextEnabled {
            windowContextProvider = { [weak self] in
                await self?.recordingOCRPrefetch.resolve()
            }
        } else {
            windowContextProvider = nil
        }

        let didProduceTranscript = await processRecordingResult(
            audioBuffer: buffer,
            recordingSessionCoordinator: recordingSessionCoordinator,
            recordingTranscriptionSession: recordingTranscriptionSession,
            archivedWindowContext: nil,
            windowContextProvider: windowContextProvider,
            shouldPaste: true,
            shouldRecordDebugSnapshot: true
        )

        if didProduceTranscript {
            overlay.dismiss(ifShowing: .transcribing)
            overlay.dismiss(ifShowing: .cleaningUp)
        } else {
            switch Self.emptyTranscriptionDisposition(forAudioSampleCount: buffer.count) {
            case .cancel:
                overlay.dismiss()
            case .showNoSoundDetected:
                overlay.show(message: .noSoundDetected)
            }
        }

        status = .ready
        releasePipeline(owner: .liveRecording)
    }

    private var escapeMonitor: Any?

    /// Esc stops the Voice Agent while it's working or talking. The monitor only listens, so Esc still
    /// reaches the app in front.
    private func startEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard let self, self.voiceAgent.isActive else { return }
                self.voiceAgent.cancel()
                self.overlay.dismiss()
            }
        }
    }

    /// An Echo Action that asked "… Say yes." and is waiting for the answer.
    private var pendingEchoAction: (action: EchoActions.Action, argument: String?, asked: Date)?

    private func processAgentCommand(_ transcript: String) async {
        let model = VoiceAgent.modelLabel
        let access = VoiceAgent.access.name
        // Clicking the reply card stops the voice and opens today's transcript file.
        overlay.onAgentReplyTapped = { [weak self] in
            self?.voiceAgent.cancel()
            self?.overlay.dismiss()
            let file = AgentTranscriptLog.fileURL(for: Date())
            if FileManager.default.fileExists(atPath: file.path) {
                AgentTranscriptLog.openInTextEdit(file)
            }
        }

        // Echo Actions run straight away; anything else goes to the agent.
        if let pending = pendingEchoAction {
            pendingEchoAction = nil
            if Date().timeIntervalSince(pending.asked) < 30 {
                if EchoActions.isYes(transcript) {
                    EchoActions.approve(pending.action)
                    if await runEchoAction(pending.action, argument: pending.argument, command: transcript) { return }
                } else if EchoActions.isNo(transcript) {
                    sayEchoActionLine("Okay, I won't.", for: transcript)
                    return
                }
            }
        }
        if EchoActions.isStop(transcript) {
            voiceAgent.cancel()
            sayEchoActionLine("Stopped.", for: transcript)
            return
        }
        EchoActions.prepareDefaultFolder()
        if let (action, argument) = EchoActions.match(transcript, in: EchoActions.load()) {
            let firstRun = EchoActions.needsFirstRunApproval(action)
            if action.needsConfirmation || firstRun {
                pendingEchoAction = (action, argument, Date())
                sayEchoActionLine(firstRun ? "First time running \(action.title). Say yes to run it."
                                           : "\(action.title)? Say yes to go ahead.", for: transcript)
                return
            }
            if await runEchoAction(action, argument: argument, command: transcript) { return }
        }

        overlay.show(message: .agentThinking)
        // The reply streams: the teleprompter shows it and Ryan starts speaking at the first full sentence,
        // while Claude is still writing the rest. The overlay reads the growing text from voiceAgent.activity.
        let replyMessage = OverlayMessage.agentReply(transcript)
        var streamedText = ""
        var replyShown = false
        var acknowledged = false
        voiceAgent.beginSpeaking()
        voiceAgent.activity.access = access
        voiceAgent.onSpeechFinished = { [weak self] in
            self?.overlay.dismiss(ifShowing: replyMessage, after: 4)
        }
        do {
            let reply = try await voiceAgent.run(transcript, onText: { [weak self] text in
                guard let self else { return }
                if !replyShown { self.overlay.show(message: replyMessage); replyShown = true }
                streamedText = text
                self.voiceAgent.updateSpeech(text)
            }, onStep: { [weak self] step in
                // Claude is doing something before it answers: open the notch to show it, and say "On it."
                guard let self else { return }
                if !replyShown { self.overlay.show(message: replyMessage); replyShown = true }
                self.voiceAgent.activity.step = step
                if !acknowledged, streamedText.isEmpty {
                    acknowledged = true
                    self.voiceAgent.acknowledge()
                }
            })
            let spoken = streamedText.isEmpty ? (reply.isEmpty ? "Done." : reply) : streamedText
            AgentTranscriptLog.append(command: transcript, reply: reply.isEmpty ? spoken : reply, model: model, access: access,
                                      actions: voiceAgent.lastActions, usage: voiceAgent.lastUsage)
            if !replyShown { overlay.show(message: replyMessage) }
            voiceAgent.finishSpeech(spoken)
        } catch is CancellationError {
            // Stopped with "stop", Esc or the reply card, or replaced by a newer command: nothing to show.
            AgentTranscriptLog.append(command: transcript, reply: "Stopped.", model: model, access: access,
                                      actions: voiceAgent.lastActions)
        } catch {
            let message = error.localizedDescription
            AgentTranscriptLog.append(command: transcript, reply: "Error: \(message)", model: model, access: access,
                                      actions: voiceAgent.lastActions)
            voiceAgent.stopSpeaking()
            voiceAgent.activity.replyText = message
            voiceAgent.activity.spokenCharacters = message.count  // not spoken: show it fully lit
            overlay.show(message: replyMessage)
            overlay.dismiss(ifShowing: replyMessage, after: 6)
        }
    }

    /// Runs an Echo Action and says its last line. Returns false when the script handed the command
    /// back (exit 75), so it goes to the agent instead.
    private func runEchoAction(_ action: EchoActions.Action, argument: String?, command: String) async -> Bool {
        let replyMessage = OverlayMessage.agentReply(command)
        voiceAgent.beginSpeaking()
        voiceAgent.activity.access = "Echo Action"
        voiceAgent.activity.step = action.title
        voiceAgent.onSpeechFinished = { [weak self] in
            self?.overlay.dismiss(ifShowing: replyMessage, after: 4)
        }
        overlay.show(message: replyMessage)
        // Most actions finish in well under a second; a slow one (a speed test) gets "On it." first.
        let acknowledge = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { self?.voiceAgent.acknowledge() }
        }
        let outcome = await EchoActions.run(action, argument: argument)
        acknowledge.cancel()
        if outcome.passToAgent {
            voiceAgent.stopSpeaking()
            return false
        }
        var reply = outcome.spoken
        if action.mode == "fullOutput", outcome.output.contains("\n") {
            reply += "\n\n```\n" + outcome.output + "\n```"
        }
        AgentTranscriptLog.append(command: command, reply: reply, model: "Echo Action", access: action.title,
                                  actions: ["Ran \(action.title)" + (argument.map { " with \u{201C}\($0)\u{201D}" } ?? "")])
        voiceAgent.activity.step = ""
        if action.mode == "silent", !outcome.failed {
            // Shown, not spoken, as in Raycast.
            voiceAgent.stopSpeaking()
            voiceAgent.activity.replyText = outcome.spoken
            voiceAgent.activity.spokenCharacters = outcome.spoken.count
            overlay.dismiss(ifShowing: replyMessage, after: 3)
        } else {
            voiceAgent.finishSpeech(outcome.spoken)
        }
        return true
    }

    /// One spoken line in the reply card, for Echo Action questions and answers.
    private func sayEchoActionLine(_ line: String, for command: String) {
        let replyMessage = OverlayMessage.agentReply(command)
        voiceAgent.beginSpeaking()
        voiceAgent.activity.access = "Echo Action"
        voiceAgent.onSpeechFinished = { [weak self] in
            self?.overlay.dismiss(ifShowing: replyMessage, after: 4)
        }
        overlay.show(message: replyMessage)
        voiceAgent.finishSpeech(line)
    }

    private func processInstructionResult(transcript: String, selectedText: String?) async {
        guard textCleanupManager.isModelDownloaded(textCleanupManager.selectedCleanupModelKind) else {
            handlePasteResult(textPaster.paste(text: transcript), text: transcript)
            return
        }

        let prompt: String
        let text: String

        if let selectedText {
            prompt = Self.instructionTransformPrompt
            text = "Instruction: \(transcript)\n\nText:\n\(selectedText)"
        } else {
            prompt = Self.instructionGeneratePrompt
            text = transcript
        }

        status = .cleaningUp
        overlay.show(message: .transforming)

        do {
            let result = try await textCleanupManager.clean(text: text, prompt: prompt)
            overlay.dismiss(ifShowing: .transforming)
            handlePasteResult(textPaster.paste(text: result), text: result)
        } catch {
            overlay.dismiss(ifShowing: .transforming)
            // Fall back to pasting the raw transcript
            handlePasteResult(textPaster.paste(text: transcript), text: transcript)
        }
    }

    func finishRecordingForTesting(
        audioBuffer: [Float],
        recordingSessionCoordinator: RecordingSessionCoordinator?,
        recordingTranscriptionSession: RecordingTranscriptionSession? = nil,
        archivedWindowContext: OCRContext?,
        windowContextProvider: WindowContextProvider? = nil
    ) async {
        _ = await processRecordingResult(
            audioBuffer: audioBuffer,
            recordingSessionCoordinator: recordingSessionCoordinator,
            recordingTranscriptionSession: recordingTranscriptionSession,
            archivedWindowContext: archivedWindowContext,
            windowContextProvider: windowContextProvider,
            shouldPaste: false,
            shouldRecordDebugSnapshot: false
        )
    }

    private func processRecordingResult(
        audioBuffer: [Float],
        recordingSessionCoordinator: RecordingSessionCoordinator?,
        recordingTranscriptionSession: RecordingTranscriptionSession?,
        archivedWindowContext: OCRContext?,
        windowContextProvider: WindowContextProvider?,
        shouldPaste: Bool,
        shouldRecordDebugSnapshot: Bool
    ) async -> Bool {
        let transcriptionResult = await transcribedTextForRecording(
            audioBuffer,
            recordingSessionCoordinator: recordingSessionCoordinator,
            recordingTranscriptionSession: recordingTranscriptionSession
        )

        guard let text = transcriptionResult.rawTranscription else {
            recordingOCRPrefetch.cancel()
            await archiveRecordingForLab(
                audioBuffer: audioBuffer,
                windowContext: archivedWindowContext,
                rawTranscription: nil,
                correctedTranscription: nil,
                cleanupUsedFallback: false,
                speakerFilteringEnabled: ignoreOtherSpeakers && selectedSpeechModelSupportsSpeakerFiltering,
                speakerFilteringRan: transcriptionResult.speakerFilteringRan,
                diarizationSummary: transcriptionResult.diarizationSummary
            )
            return false
        }

        // Other languages keep it: "um" is a real word in Portuguese.
        let spoken = preferredLanguage == "auto" || preferredLanguage == "en" ? Self.removingHesitations(text) : text
        var windowContext = archivedWindowContext
        if cleanupEnabled && canAttemptCleanup && !Self.isTooShortToClean(spoken) {
            activeCleanupAttempted = true
            if frontmostWindowContextEnabled,
               windowContext == nil,
               let resolvedWindowContext = await windowContextProvider?() {
                windowContext = resolvedWindowContext.context
            }
            status = .cleaningUp
            if shouldPaste {
                overlay.show(message: .cleaningUp)
            }
        } else {
            recordingOCRPrefetch.cancel()
        }

        let cleanupResult = await cleanedTranscriptionResult(spoken, windowContext: windowContext)
        let finalText = cleanupResult.text
        activeCleanupAttempted = cleanupResult.attemptedCleanup

        await archiveRecordingForLab(
            audioBuffer: audioBuffer,
            windowContext: windowContext,
            rawTranscription: text,
            correctedTranscription: finalText,
            cleanupUsedFallback: cleanupResult.cleanupUsedFallback,
            speakerFilteringEnabled: ignoreOtherSpeakers && selectedSpeechModelSupportsSpeakerFiltering,
            speakerFilteringRan: transcriptionResult.speakerFilteringRan,
            diarizationSummary: transcriptionResult.diarizationSummary
        )

        if shouldRecordDebugSnapshot {
            recordCleanupDebugSnapshot(
                rawTranscription: text,
                windowContext: windowContext,
                cleanedOutput: finalText,
                attemptedCleanup: cleanupResult.attemptedCleanup
            )
        }

        if shouldPaste {
            handlePasteResult(textPaster.paste(text: finalText), text: finalText)
        }

        return true
    }

    private func transcribedTextForRecording(
        _ audioBuffer: [Float],
        recordingSessionCoordinator: RecordingSessionCoordinator?,
        recordingTranscriptionSession: RecordingTranscriptionSession?
    ) async -> RecordingTranscriptionResult {
        let diarizationTask = recordingSessionCoordinator.map { coordinator in
            Task {
                await coordinator.finishResult()
            }
        }
        let concurrentRecordingTranscriptionSession: RecordingTranscriptionSession?
        if let recordingTranscriptionSession,
           recordingTranscriptionSession.supportsConcurrentFinalization {
            concurrentRecordingTranscriptionSession = recordingTranscriptionSession
        } else {
            concurrentRecordingTranscriptionSession = nil
        }

        let streamedTranscriptTask = concurrentRecordingTranscriptionSession.map { session in
            Task<String?, Never> {
                await session.finishTranscription()?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var diarizationSummary: DiarizationSummary?
        if let diarizationTask {
            let diarizationResult = await diarizationTask.value
            diarizationSummary = diarizationResult.summary

            if diarizationResult.summary.usedFallback == false,
               let filteredTranscript = diarizationResult.filteredTranscript?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               filteredTranscript.isEmpty == false {
                recordingTranscriptionSession?.cancel()
                return RecordingTranscriptionResult(
                    rawTranscription: filteredTranscript,
                    speakerFilteringRan: true,
                    diarizationSummary: diarizationResult.summary
                )
            }
        }

        if let streamedTranscriptTask,
           let streamedTranscript = await streamedTranscriptTask.value,
           streamedTranscript.isEmpty == false {
            return RecordingTranscriptionResult(
                rawTranscription: streamedTranscript,
                speakerFilteringRan: recordingSessionCoordinator != nil,
                diarizationSummary: diarizationSummary
            )
        }

        if concurrentRecordingTranscriptionSession == nil,
           let recordingTranscriptionSession,
           let streamedTranscript = await recordingTranscriptionSession.finishTranscription()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           streamedTranscript.isEmpty == false {
            return RecordingTranscriptionResult(
                rawTranscription: streamedTranscript,
                speakerFilteringRan: recordingSessionCoordinator != nil,
                diarizationSummary: diarizationSummary
            )
        }

        if let recordingTranscriptionSession,
           recordingTranscriptionSession.allowsBatchFallback == false {
            return RecordingTranscriptionResult(
                rawTranscription: nil,
                speakerFilteringRan: recordingSessionCoordinator != nil,
                diarizationSummary: diarizationSummary
            )
        }

        return RecordingTranscriptionResult(
            rawTranscription: await transcribeAudioBuffer(audioBuffer),
            speakerFilteringRan: recordingSessionCoordinator != nil,
            diarizationSummary: diarizationSummary
        )
    }

    private func transcribeAudioBuffer(_ audioBuffer: [Float]) async -> String? {
        if let transcribeAudioBufferOverride {
            return transcribeAudioBufferOverride(audioBuffer)
        }

        let language = preferredLanguage == "auto" ? nil : preferredLanguage
        return await transcriber.transcribe(audioBuffer: audioBuffer, language: language)
    }

    func cleanedTranscription(_ text: String) async -> String {
        let result = await cleanedTranscriptionResult(text, windowContext: nil)
        return result.text
    }

    /// After a paste: the notch peek when Settings asks for it, otherwise the "Copied" pill if the paste had nowhere to go.
    private func handlePasteResult(_ result: PasteResult, text: String) {
        let pasteFailed = result == .copiedToClipboard
        if DictationNotchMode.current.shows(pasteFailed: pasteFailed) {
            overlay.showTranscriptPeek(text, pasteFailed: pasteFailed)
        } else if pasteFailed {
            showClipboardFallbackMessage()
        }
    }

    private func showClipboardFallbackMessage() {
        overlay.show(message: .clipboardFallback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.overlay.dismiss(ifShowing: .clipboardFallback)
        }
    }

    private let settingsController = SettingsWindowController()
    private let promptEditorController = PromptEditorController()
    private let cleanupTranscriptWindowController = CleanupTranscriptWindowController()
    private lazy var meetingTranscriptWindowController: MeetingTranscriptWindowController = {
        let controller = MeetingTranscriptWindowController()
        controller.shouldFloatWhileRecording = { [weak self] in
            self?.meetingWindowFloatsWhileRecording ?? true
        }
        controller.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        controller.onStartRecording = { [weak self] name, detectedMeeting -> MeetingSession? in
            self?.createMeetingSession(name: name, detectedMeeting: detectedMeeting)
        }
        controller.onStopRecording = { [weak self] session in
            Task {
                await self?.finishMeetingSession(session, logPrefix: "Meeting stopped")
            }
        }
        controller.onGenerateSummary = { [weak self] transcript in
            Task { await self?.generateMeetingSummary(for: transcript) }
        }
        controller.onAskQuestion = { [weak self] question, context in
            guard let self else { return "Not available" }
            let systemPrompt = """
            You are answering a question about meeting notes and transcripts. \
            Use ONLY the meeting content provided below. Be concise and specific. \
            If the answer isn't in the content, say "I didn't find that in your meetings." \
            Do NOT make up information. Reference which meeting the answer came from.
            """
            let userInput = """
            \(context)

            Question: \(question)
            """
            // Prefer 8B model for Q&A (larger context), fall back to loaded cleanup model
            let qaModelKind: LocalCleanupModelKind = .qwen35_9b_q4_k_m
            let modelToUse: LocalCleanupModelKind? = self.textCleanupManager.isModelDownloaded(qaModelKind) ? qaModelKind : nil
            do {
                return try await self.textCleanupManager.clean(text: userInput, prompt: systemPrompt, modelKind: modelToUse)
            } catch {
                return "Could not answer — download the Qwen 3.5 9B model in Settings > Models for best results."
            }
        }
        controller.onSelectCleanupModel = { [weak self] kind in
            guard let self else { return }
            self.textCleanupManager.selectedCleanupModelKind = kind
            Task { await self.textCleanupManager.loadModel(kind: kind) }
        }
        return controller
    }()
    private let meetingDetector = MeetingDetector()
    @Published var activeMeetingSession: MeetingSession?

    var canReloadAudioInput: Bool {
        Self.isLiveRecordingNoInputError(errorMessage)
    }

    func resetAudioEngine() {
        audioRecorder.targetDeviceID = selectedInputDeviceIDProvider()
        resetAudioRecorder()

        if shouldClearLiveRecordingNoInputErrorAfterAudioReset {
            errorMessage = nil
            status = .ready
        }
    }

    func showSettings() {
        settingsController.show(appState: self)
    }

    func showPromptEditor() {
        promptEditorController.show(appState: self)
    }

    func showCleanupTranscript(_ transcript: TranscriptionLabCleanupTranscript) {
        cleanupTranscriptWindowController.show(transcript: transcript)
    }

    // MARK: - Meeting Transcript

    /// Creates a new MeetingSession, starts recording, and returns it.
    /// Called by the window state when the user clicks "+" or auto-detection triggers.
    func createMeetingSession(name: String, detectedMeeting: DetectedMeeting? = nil) -> MeetingSession? {
        guard PermissionChecker.hasScreenRecordingPermission() else {
            PermissionChecker.requestScreenRecordingPermission()
            return nil
        }

        let saveDir = MeetingTranscriptSettings.effectiveSaveDirectory()
        let session = MeetingSession(
            meetingName: name,
            detectedMeeting: detectedMeeting,
            transcriber: transcriber,
            saveDirectory: saveDir
        )
        session.onAutoStopRequested = { [weak self] session in
            Task {
                await self?.finishMeetingSession(session, logPrefix: "Meeting transcription auto-stopped")
            }
        }
        activeMeetingSession = session

        Task {
            do {
                try await session.start()
            } catch {
                activeMeetingSession = nil
            }
        }

        return session
    }

    func startMeetingTranscription(
        meetingName: String,
        skipConsent: Bool = false,
        sourceURL: String? = nil,
        detectedMeeting: DetectedMeeting? = nil
    ) {
        meetingTranscriptWindowController.show()
        meetingTranscriptWindowController.requestRecording(
            name: meetingName,
            skipConsent: skipConsent,
            sourceURL: sourceURL,
            detectedMeeting: detectedMeeting
        )
    }

    /// Starts a meeting transcription immediately (no auto-detection, no consent prompt).
    /// Captures mic + system audio so it picks up the user even before anyone else speaks.
    /// Invoked from the "Start Meeting" menu-bar item.
    func startMeetingNow() {
        guard activeMeetingSession == nil else { return }
        startMeetingTranscription(meetingName: Self.defaultMeetingName(), skipConsent: true)
    }

    private static func defaultMeetingName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Meeting — \(formatter.string(from: Date()))"
    }

    func showMeetingTranscriptWindow() {
        meetingTranscriptWindowController.show()
    }

    func showOrCreateMeetingWindow() {
        meetingTranscriptWindowController.show()
    }

    func refreshMeetingTranscriptWindowPresentation() {
        meetingTranscriptWindowController.refreshPresentation()
    }

    func generateMeetingSummary(for transcript: MeetingTranscript) async {
        guard !transcript.segments.isEmpty else {
            transcript.summaryError = "There's no transcript to summarize yet. Record or import a meeting with spoken content first."
            return
        }
        transcript.isGeneratingSummary = true
        transcript.summaryError = nil
        let generator = MeetingSummaryGenerator(cleanupManager: textCleanupManager)
        do {
            let result = try await generator.generateSummary(
                transcript: transcript,
                chunkPrompt: MeetingSummaryGenerator.defaultPrompt,
                finalPrompt: meetingSummaryPrompt
            )
            transcript.summary = result
            if result == nil {
                transcript.summaryError = "The model returned an empty summary. Try selecting a different cleanup model in Settings → Cleanup model."
            }
        } catch let error as CleanupBackendError {
            switch error {
            case .unavailable:
                transcript.summaryError = "The cleanup model isn’t loaded. In Settings → Cleanup model, pick a model you’ve downloaded, then try again."
            case .unusableOutput:
                transcript.summaryError = "The model produced unusable output. Try a larger cleanup model (e.g. Qwen 3.5 4B) in Settings → Cleanup model."
            }
        } catch let error as CleanupTimeoutError {
            transcript.summaryError = "\(error.localizedDescription) Try a smaller cleanup model in Settings → Cleanup model."
        } catch {
            transcript.summaryError = "Summary failed: \(error.localizedDescription)"
        }
        transcript.isGeneratingSummary = false
        // The summary loaded a cleanup model; go back to what dictation needs
        // (nothing when cleanup is off) so it doesn't stay in memory.
        await refreshCleanupModelState()
    }

    // MARK: - Voice Agent notice

    static let termsURL = URL(string: "https://echooneapp.vercel.app/terms/")!
    private static let voiceAgentTermsKey = "voiceAgentTermsAccepted"
    /// Bump when the notice's wording changes in a way people should see again.
    private static let voiceAgentTermsVersion = 1

    /// True once the person has accepted the Voice Agent notice. Otherwise shows it and returns
    /// whether they accepted just now (they then press the keys again to talk).
    private func voiceAgentTermsAccepted() -> Bool {
        if UserDefaults.standard.integer(forKey: Self.voiceAgentTermsKey) >= Self.voiceAgentTermsVersion { return true }
        let alert = NSAlert()
        alert.messageText = "Before you use the Voice Agent"
        alert.informativeText = """
        The Voice Agent hands what you say to the Claude Code or Codex on your Mac. Depending on the access level you pick, it can create, change, move and delete files and run commands. AI can misunderstand you or get things wrong.

        • You're in charge of what you ask it to do. Check its work, and keep a backup (Time Machine works).
        • Echo One is free and comes as is. Its maker isn't responsible for lost files or data, or for costs on your Claude or ChatGPT account.
        • Your commands go to Anthropic or OpenAI under your own account and their terms.

        After you agree, press the Voice Agent keys again to talk.
        """
        alert.alertStyle = .informational
        alert.icon = NSImage(named: "AppIcon")
        alert.addButton(withTitle: "I Understand")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Read the Terms")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            UserDefaults.standard.set(Self.voiceAgentTermsVersion, forKey: Self.voiceAgentTermsKey)
            UserDefaults.standard.set(Date(), forKey: Self.voiceAgentTermsKey + "Date")
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(Self.termsURL)
        default:
            break
        }
        return false
    }

    // MARK: - Form Fill (beta)

    /// BETA — fills the frontmost window's form fields from the saved profile.
    /// Invoked from the "Fill Form (beta)" menu-bar item.
    func fillFrontmostForm() {
        let result = FormFiller().fillFrontmostForm()
        let alert = NSAlert()
        if result.profileEmpty {
            alert.messageText = "No form-fill profile yet"
            alert.informativeText = "Add your details in Settings → Form Fill (beta), then try again."
        } else if result.noFieldsFound {
            alert.messageText = "No fillable fields found"
            alert.informativeText = "Echo One couldn't find text fields in the frontmost window."
        } else {
            alert.messageText = "Filled \(result.filled) field\(result.filled == 1 ? "" : "s")"
            var detail = ""
            if result.skippedSecure > 0 { detail += "Skipped \(result.skippedSecure) password field(s). " }
            if result.unmatched > 0 { detail += "\(result.unmatched) field(s) didn't match your profile." }
            alert.informativeText = detail.isEmpty ? "All matched fields were filled." : detail
        }
        alert.runModal()
    }

    func stopMeetingTranscription() {
        guard let session = activeMeetingSession else { return }
        Task {
            await finishMeetingSession(session, logPrefix: "Meeting transcription stopped")
        }
    }

    func setupMeetingDetector() {
        guard meetingTranscriptEnabled, meetingAutoDetectEnabled else {
            meetingDetector.stop()
            return
        }

        meetingDetector.onMeetingDetected = { [weak self] meeting in
            guard let self = self, self.activeMeetingSession == nil else { return }
            self.startMeetingTranscription(
                meetingName: meeting.suggestedName,
                skipConsent: meeting.isVideo,
                sourceURL: meeting.sourceURL,
                detectedMeeting: meeting
            )
        }

        meetingDetector.start()
    }

    private func finishMeetingSession(_ session: MeetingSession, logPrefix: String) async {
        await session.stop()
        if openMeetingFolderOnEnd {
            revealMeetingInFinder(session)
        }
        if activeMeetingSession === session {
            activeMeetingSession = nil
        }
    }

    /// Opens Finder when a meeting ends — reveals the saved transcript file if available,
    /// otherwise opens the meetings folder.
    private func revealMeetingInFinder(_ session: MeetingSession) {
        if let url = session.fileURL {
            NSWorkspace.shared.selectFile(
                url.path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
        } else {
            NSWorkspace.shared.open(MeetingTranscriptSettings.effectiveSaveDirectory())
        }
    }

    private var shortcutBindings: [ChordAction: KeyChord] {
        [
            .pushToTalk: pushToTalkChord,
            .toggleToTalk: toggleToTalkChord,
            .instructionMode: instructionModeChord
        ].merging(voiceAgentEnabled ? [.voiceAgent: voiceAgentChord] : [:]) { current, _ in current }
    }

    private func persistShortcutBindingsIfNeeded() {
        try? chordBindingStore.setBinding(pushToTalkChord, for: .pushToTalk)
        try? chordBindingStore.setBinding(toggleToTalkChord, for: .toggleToTalk)
        try? chordBindingStore.setBinding(instructionModeChord, for: .instructionMode)
        try? chordBindingStore.setBinding(voiceAgentChord, for: .voiceAgent)
    }

    private var canAttemptCleanup: Bool {
        textCleanupManager.isReady
    }

    var shouldLoadLocalCleanupModels: Bool {
        cleanupEnabled
    }

    private func cleanedTranscriptionResult(
        _ text: String,
        windowContext: OCRContext?
    ) async -> CleanupResult {
        if let cleanedTranscriptionResultOverride {
            return await cleanedTranscriptionResultOverride(text, windowContext)
        }

        guard cleanupEnabled, !Self.isTooShortToClean(text) else {
            return (text: text, prompt: cleanupPrompt, attemptedCleanup: false, cleanupUsedFallback: false)
        }

        let activeCleanupPrompt: String
        if canAttemptCleanup {
            activeCleanupPrompt = activeCleanupPromptComponents(windowContext: windowContext).fullPrompt
        } else {
            activeCleanupPrompt = languageAwareCleanupPrompt
        }

        let cleanedResult = await textCleaner.cleanWithPerformance(
            text: text,
            prompt: activeCleanupPrompt,
            modelKind: textCleanupManager.selectedCleanupModelKind
        )
        return (
            text: cleanedResult.text,
            prompt: activeCleanupPrompt,
            attemptedCleanup: canAttemptCleanup,
            cleanupUsedFallback: cleanedResult.usedFallback
        )
    }

    /// Drops "um" and "uh" (and "umm", "uhh") before cleanup, so they go even when the model is skipped or misses them.
    /// A comma left around the filler goes with it, a full stop it carried moves to the word before, and a capital it had passes to the next word.
    static func removingHesitations(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var index = 0
        var removedAny = false
        while index < words.count {
            let word = words[index]
            let core = word.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?…"))
            guard core.range(of: "^u+(m+|h+)$", options: [.regularExpression, .caseInsensitive]) != nil else {
                index += 1
                continue
            }
            removedAny = true
            let trailing = word.drop(while: { $0.isLetter })
            if index > 0 {
                var previous = words[index - 1]
                if trailing.contains(where: { ".!?".contains($0) }) {
                    if !(previous.last.map { ".!?".contains($0) } ?? false) {
                        if previous.last == "," { previous.removeLast() }
                        previous += trailing.filter { ".!?".contains($0) }.prefix(1)
                    }
                } else if trailing.contains(",") && previous.last == "," {
                    previous.removeLast()
                }
                words[index - 1] = previous
            }
            if core.first?.isUppercase == true, index + 1 < words.count {
                let next = words[index + 1]
                words[index + 1] = next.prefix(1).uppercased() + next.dropFirst()
            }
            words.remove(at: index)
        }
        guard removedAny, !words.isEmpty else { return text }
        return words.joined(separator: " ")
    }

    /// One or two words have nothing to clean up, so they skip the cleanup model and paste straight away.
    static func isTooShortToClean(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        return words.count < 3
    }

    private var languageAwareCleanupPrompt: String {
        if preferredLanguage != "auto" && preferredLanguage != "en" {
            let langName = Locale.current.localizedString(forLanguageCode: preferredLanguage) ?? preferredLanguage
            return cleanupPrompt + "\n\nThe transcription is in \(langName). Preserve the original language — do not translate to English."
        }

        return cleanupPrompt
    }

    private func activeCleanupPromptComponents(windowContext: OCRContext?) -> CleanupPromptComponents {
        cleanupPromptBuilder.buildPromptComponents(
            basePrompt: languageAwareCleanupPrompt,
            windowContext: windowContext,
            preferredTranscriptions: correctionStore.preferredTranscriptions,
            commonlyMisheard: correctionStore.commonlyMisheard,
            includeWindowContext: frontmostWindowContextEnabled
        )
    }

    var ocrCustomWords: [String] {
        correctionStore.preferredOCRCustomWords
    }

    func recordCleanupDebugSnapshot(
        rawTranscription: String,
        windowContext: OCRContext?,
        cleanedOutput: String,
        attemptedCleanup: Bool
    ) {
    }

    func archiveRecordingForLab(
        audioBuffer: [Float],
        windowContext: OCRContext?,
        rawTranscription: String?,
        correctedTranscription: String?,
        cleanupUsedFallback: Bool,
        speakerFilteringEnabled: Bool = false,
        speakerFilteringRan: Bool = false,
        diarizationSummary: DiarizationSummary? = nil
    ) async {
        guard transcriptionLabEnabled, audioBuffer.count >= Self.minimumArchivedRecordingSampleCount else {
            return
        }

        let entryID = UUID()
        let audioFileName = "\(entryID.uuidString).wav"
        do {
            let audioData = try AudioRecorder.serializePlayableArchiveAudioBuffer(audioBuffer)
            let entry = TranscriptionLabEntry(
                id: entryID,
                createdAt: Date(),
                audioFileName: audioFileName,
                audioDuration: Double(audioBuffer.count) / Self.archivedRecordingSampleRate,
                windowContext: windowContext,
                rawTranscription: rawTranscription,
                correctedTranscription: correctedTranscription,
                speechModelID: speechModel,
                cleanupModelName: cleanupEnabled ? textCleanupManager.selectedCleanupModelDisplayName : "Cleanup disabled",
                cleanupUsedFallback: cleanupUsedFallback,
                speakerFilteringEnabled: speakerFilteringEnabled,
                speakerFilteringRan: speakerFilteringRan,
                speakerFilteringUsedFallback: diarizationSummary?.usedFallback ?? false,
                diarizationSummary: diarizationSummary
            )
            let stageTimings = TranscriptionLabStageTimings(
                transcriptionDuration: nil,
                cleanupDuration: nil
            )
            try transcriptionLabStore.insert(entry, audioData: audioData, stageTimings: stageTimings)
        } catch {
        }
    }

    func loadTranscriptionLabEntries() throws -> [TranscriptionLabEntry] {
        try transcriptionLabStore.loadEntries()
    }

    func loadTranscriptionLabStageTimings() throws -> [UUID: TranscriptionLabStageTimings] {
        try transcriptionLabStore.loadStageTimings()
    }

    func loadTranscriptionLabSpeakerProfiles(
        for entryID: UUID
    ) throws -> [TranscriptionLabSpeakerProfile] {
        try transcriptionLabSpeakerProfileStore.loadProfiles(for: entryID)
    }

    func loadAllTranscriptionLabSpeakerProfiles() throws -> [TranscriptionLabSpeakerProfile] {
        try transcriptionLabSpeakerProfileStore.loadAllProfiles()
    }

    func upsertTranscriptionLabSpeakerProfile(_ profile: TranscriptionLabSpeakerProfile) throws {
        try transcriptionLabSpeakerProfileStore.upsert(profile)
    }

    func transcriptionLabAudioURL(for entry: TranscriptionLabEntry) -> URL {
        transcriptionLabStore.audioURL(for: entry.audioFileName)
    }

    func rerunTranscriptionLabTranscription(
        _ entry: TranscriptionLabEntry,
        speechModelID: String,
        speakerTaggingEnabled: Bool
    ) async throws -> TranscriptionLabTranscriptionResult {
        guard acquirePipeline(for: .transcriptionLab) else {
            throw TranscriptionLabRunnerError.pipelineBusy
        }

        let preferredSpeechModelID = speechModel
        let runner = makeTranscriptionLabRunner()

        do {
            let result = try await runner.rerunTranscription(
                entry: entry,
                speechModelID: speechModelID,
                speakerTaggingEnabled: speakerTaggingEnabled,
                acquirePipeline: { true },
                releasePipeline: {}
            )
            await restorePreferredSpeechModelIfNeeded(preferredSpeechModelID)
            releasePipeline(owner: .transcriptionLab)
            return result
        } catch {
            await restorePreferredSpeechModelIfNeeded(preferredSpeechModelID)
            releasePipeline(owner: .transcriptionLab)
            throw error
        }
    }

    func rerunTranscriptionLabCleanup(
        _ entry: TranscriptionLabEntry,
        rawTranscription: String,
        cleanupModelKind: LocalCleanupModelKind,
        prompt: String,
        includeWindowContext: Bool
    ) async throws -> TranscriptionLabCleanupResult {
        guard acquirePipeline(for: .transcriptionLab) else {
            throw TranscriptionLabRunnerError.pipelineBusy
        }

        let runner = makeTranscriptionLabRunner()

        do {
            let result = try await runner.rerunCleanup(
                entry: entry,
                rawTranscription: rawTranscription,
                cleanupModelKind: cleanupModelKind,
                prompt: prompt,
                includeWindowContext: includeWindowContext,
                acquirePipeline: { true },
                releasePipeline: {}
            )
            releasePipeline(owner: .transcriptionLab)
            return result
        } catch {
            releasePipeline(owner: .transcriptionLab)
            throw error
        }
    }

    func updateShortcut(_ chord: KeyChord, for action: ChordAction) {
        let previousPushChord = pushToTalkChord
        let previousToggleChord = toggleToTalkChord

        do {
            try chordBindingStore.setBinding(chord, for: action)
            shortcutErrorMessage = nil

            switch action {
            case .pushToTalk:
                pushToTalkChord = chord
            case .toggleToTalk:
                toggleToTalkChord = chord
            case .instructionMode:
                instructionModeChord = chord
            case .voiceAgent:
                voiceAgentChord = chord
            }

            hotkeyMonitor.updateBindings(shortcutBindings)
        } catch {
            pushToTalkChord = previousPushChord
            toggleToTalkChord = previousToggleChord
            shortcutErrorMessage = "That shortcut is already in use."
        }
    }

    func setShortcutCaptureActive(_ isActive: Bool) {
        hotkeyMonitor.setSuspended(isActive)
    }

    func setCleanupEnabled(_ enabled: Bool) {
        cleanupEnabled = enabled
        Task {
            await refreshCleanupModelState()
        }
    }

    func updateCleanupBackend(_ backend: CleanupBackendOption) {
        cleanupBackend = backend
        Task {
            await refreshCleanupModelState()
        }
    }

    func prepareForTermination() {
        recordingOCRPrefetch.cancel()
        textCleanupManager.shutdownBackend()
        meetingDetector.stop()
        if let session = activeMeetingSession {
            Task { await session.stop() }
        }
    }

    func acquirePipeline(for owner: PipelineOwner) -> Bool {
        guard pipelineOwner == nil else {
            return false
        }

        pipelineOwner = owner
        return true
    }

    func releasePipeline(owner: PipelineOwner) {
        guard pipelineOwner == owner else {
            return
        }

        pipelineOwner = nil
    }

    private func refreshCleanupModelState() async {
        guard cleanupEnabled else {
            textCleanupManager.unloadModel()
            objectWillChange.send()
            return
        }

        let shouldLoadLocalModels = shouldLoadLocalCleanupModels

        if shouldLoadLocalModels {
            await textCleanupManager.loadModel()
        } else {
            textCleanupManager.unloadModel()
        }

        objectWillChange.send()
    }

    private func mergedSpeakerSpans(
        from spans: [DiarizationSummary.Span]
    ) -> [DiarizationSummary.MergedSpan] {
        let sortedSpans = spans.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }

        var mergedSpans: [DiarizationSummary.MergedSpan] = []
        for span in sortedSpans where span.duration > 0 {
            if let lastSpan = mergedSpans.last,
               span.startTime <= lastSpan.endTime {
                mergedSpans[mergedSpans.count - 1] = DiarizationSummary.MergedSpan(
                    startTime: lastSpan.startTime,
                    endTime: max(lastSpan.endTime, span.endTime)
                )
            } else {
                mergedSpans.append(
                    DiarizationSummary.MergedSpan(
                        startTime: span.startTime,
                        endTime: span.endTime
                    )
                )
            }
        }

        return mergedSpans
    }

    private func extractSpeakerAudio(
        from audioBuffer: [Float],
        spans: [DiarizationSummary.MergedSpan],
        sampleRate: Double = 16_000
    ) -> [Float] {
        guard audioBuffer.isEmpty == false else {
            return []
        }

        var extractedAudio: [Float] = []
        for span in spans where span.duration > 0 {
            let startIndex = max(Int((span.startTime * sampleRate).rounded(.down)), 0)
            let endIndex = min(Int((span.endTime * sampleRate).rounded(.up)), audioBuffer.count)
            guard startIndex < endIndex else {
                continue
            }

            extractedAudio.append(contentsOf: audioBuffer[startIndex..<endIndex])
        }

        return extractedAudio
    }

    private func makeTranscriptionLabRunner() -> TranscriptionLabRunner {
        TranscriptionLabRunner(
            loadAudioBuffer: { [transcriptionLabStore] entry in
                let audioData = try Data(contentsOf: transcriptionLabStore.audioURL(for: entry.audioFileName))
                return try AudioRecorder.deserializeArchivedAudioBuffer(from: audioData)
            },
            loadSpeechModel: { [weak self] modelID in
                guard let self else { return }
                await self.loadSpeechModel(name: modelID)
            },
            transcribe: { [transcriber] audioBuffer in
                await transcriber.transcribe(audioBuffer: audioBuffer)
            },
            runSpeakerTagging: { [weak self] audioBuffer in
                guard let self else { return nil }
                return await self.modelManager.transcribeWithSpeakerTagging(audioBuffer: audioBuffer)
            },
            resolveSpeakerProfiles: { _, _, _, _ in [] },
            clean: { [textCleaner] text, activePrompt, modelKind in
                await textCleaner.cleanWithPerformance(
                    text: text,
                    prompt: activePrompt,
                    modelKind: modelKind
                )
            },
            correctionStore: correctionStore
        )
    }

    private func restorePreferredSpeechModelIfNeeded(_ preferredSpeechModelID: String) async {
        guard modelManager.modelName != preferredSpeechModelID || !modelManager.isReady else {
            return
        }

        await loadSpeechModel(name: preferredSpeechModelID)
    }

    func loadSpeechModel(name: String) async {
        await modelManager.loadModel(name: name)
        let nextPresentation = Self.nextSpeechModelPresentation(
            managerState: modelManager.state,
            managerError: modelManager.error,
            currentStatus: status,
            currentErrorMessage: errorMessage
        )
        status = nextPresentation.status
        errorMessage = nextPresentation.errorMessage
    }

    static func nextSpeechModelPresentation(
        managerState: ModelManagerState,
        managerError: Error?,
        currentStatus: AppStatus,
        currentErrorMessage: String?
    ) -> (status: AppStatus, errorMessage: String?) {
        switch managerState {
        case .error:
            let shouldClearSpeechModelError = currentErrorMessage?.hasPrefix(speechModelErrorPrefix) == true
            let preservedErrorMessage = shouldClearSpeechModelError ? nil : currentErrorMessage
            return (
                .error,
                preservedErrorMessage
            )
        case .ready:
            let shouldClearSpeechModelError = currentErrorMessage?.hasPrefix(speechModelErrorPrefix) == true
            let nextStatus: AppStatus = shouldClearSpeechModelError && currentStatus == .error
                ? .ready
                : currentStatus
            return (
                nextStatus,
                shouldClearSpeechModelError ? nil : currentErrorMessage
            )
        case .idle, .loading:
            return (currentStatus, currentErrorMessage)
        }
    }

    private var shouldClearLiveRecordingNoInputErrorAfterAudioReset: Bool {
        status == .error && !isRecording && !isTranscribing && Self.isLiveRecordingNoInputError(errorMessage)
    }

    private static func isLiveRecordingNoInputError(_ message: String?) -> Bool {
        message == liveRecordingNoInputErrorMessage
    }

}
