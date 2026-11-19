import AppKit
import AVFoundation
import Foundation

// The Voice Agent ships in the released Echo One app, but its engine is not open source.
// This file stands in for it so the rest of the app builds: it keeps the names the Settings
// screen, the overlay and Echo Actions use, and leaves out everything that talks to a coding
// agent, the reply voice and the transcript log.
//
// In a build made from this source, the Voice Agent shortcut still runs Echo Actions and reads
// their answers with the Mac's built-in voice. Any other command gets one spoken line saying
// the Voice Agent isn't part of this build.

@MainActor
final class VoiceAgent: NSObject, AVSpeechSynthesizerDelegate {
    static let notInThisBuild = "The Voice Agent isn't part of the open-source build."

    /// Which coding agent the Voice Agent talks to. Picked in Settings → Voice Agent → Agent.
    enum Provider: String, CaseIterable, Identifiable {
        case claude, codex

        var id: String { rawValue }

        var name: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            }
        }

        var shortName: String {
            switch self {
            case .claude: return "Claude"
            case .codex: return "Codex"
            }
        }

        var binaryName: String { rawValue }

        var downloadURL: URL {
            switch self {
            case .claude: return URL(string: "https://claude.com/product/claude-code")!
            case .codex: return URL(string: "https://developers.openai.com/codex")!
            }
        }
    }

    static let providerDefaultsKey = "voiceAgentProvider"

    static var provider: Provider {
        UserDefaults.standard.string(forKey: providerDefaultsKey).flatMap(Provider.init(rawValue:)) ?? .claude
    }

    /// How much the agent may do. Picked in Settings → Voice Agent.
    enum Access: String, CaseIterable, Identifiable {
        case askOnly, editFiles, sandbox, full

        var id: String { rawValue }

        var name: String {
            switch self {
            case .askOnly: return "Ask only"
            case .editFiles: return "Edit files"
            case .sandbox: return "Sandbox"
            case .full: return "Full"
            }
        }

        var detail: String {
            switch self {
            case .askOnly: return "Reads files and searches the web to answer. Can't change anything."
            case .editFiles: return "Can also create and edit files in the folder. No terminal commands."
            case .sandbox: return "Can do anything, but only inside its own Echo One Sandbox folder. The rest of the Mac is off limits."
            case .full: return "Can edit files and run terminal commands, like Claude Code in auto mode."
            }
        }
    }

    static let accessDefaultsKey = "voiceAgentAccess"
    static let folderDefaultsKey = "voiceAgentFolder"
    static let modelDefaultsKey = "voiceAgentModel"
    static let rulesDefaultsKey = "voiceAgentRules"

    static var access: Access {
        UserDefaults.standard.string(forKey: accessDefaultsKey).flatMap(Access.init(rawValue:)) ?? .askOnly
    }

    static func defaultFolder() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: folderDefaultsKey), !path.isEmpty {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return defaultFolder()
    }

    static let sandboxFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Echo One Sandbox")

    static func workingFolder(for access: Access) -> URL {
        access == .sandbox ? sandboxFolder : folder
    }

    static let defaultModel = "claude-haiku-5-5"
    static let models: [(id: String, name: String)] = [
        ("claude-haiku-5-5", "Haiku 5.5 (fastest)"),
        ("claude-sonnet-5-5", "Sonnet 5.5"),
        ("claude-opus-5-5", "Opus 5.5"),
        ("claude-fable-5-1", "Fable 5.1 (smartest, slowest)")
    ]

    static var model: String {
        UserDefaults.standard.string(forKey: modelDefaultsKey) ?? defaultModel
    }

    nonisolated static func codexDefaultModel() -> String? { nil }

    static var modelLabel: String {
        switch provider {
        case .claude: return models.first { $0.id == model }?.name ?? model
        case .codex: return "Codex"
        }
    }

    enum ReplyVoice: String, CaseIterable {
        case kokoro, ryan

        var name: String {
            switch self {
            case .kokoro: return "Heart (Kokoro)"
            case .ryan: return "Ryan (Qwen3-TTS)"
            }
        }
    }

    static let voiceDefaultsKey = "voiceAgentVoice"
    static let speedDefaultsKey = "voiceAgentSpeechSpeed"
    static let showsReplyTextDefaultsKey = "voiceAgentShowsReply"
    static var showsReplyText: Bool {
        UserDefaults.standard.object(forKey: showsReplyTextDefaultsKey) as? Bool ?? true
    }
    static let defaultSpeechSpeed = 1.2
    static let speechSpeeds: [Double] = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
    static let ryanVoiceInstalled = false

    struct AgentUsage: Equatable {
        let tokens: Int
        let cachedTokens: Int
        let costUSD: Double
        var onAPIKey = false
        var onCodex = false
    }

    var onSpeechFinished: (() -> Void)?
    /// What the overlay's orb and reply card read.
    let activity = AgentVoiceActivity()
    let lastActions: [String] = []
    let lastUsage: AgentUsage? = nil

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func prepareClaude() {}
    func warmUpVoice() {}
    func acknowledge() {}

    var isActive: Bool { synthesizer.isSpeaking }

    func cancel() {
        stopSpeaking()
    }

    func run(_ command: String, onText: @escaping @MainActor (String) -> Void = { _ in },
             onStep: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
        Self.notInThisBuild
    }

    func beginSpeaking() {
        stopSpeaking()
        activity.reset()
    }

    func updateSpeech(_ text: String) {
        activity.replyText = text
    }

    /// Shows the line in the reply card and reads it with the Mac's built-in voice.
    func finishSpeech(_ text: String) {
        activity.replyText = text
        activity.level = 0.4
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        activity.level = 0
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.activity.level = 0
            self.onSpeechFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let end = characterRange.location + characterRange.length
        Task { @MainActor in self.activity.spokenCharacters = end }
    }
}

/// Live loudness and teleprompter position for the overlay's orb and reply card.
final class AgentVoiceActivity: ObservableObject {
    @Published var level: Float = 0
    @Published var spokenCharacters = 0
    @Published var replyText = ""
    @Published var step = ""
    @Published var access = ""

    func reset() {
        level = 0
        spokenCharacters = 0
        replyText = ""
        step = ""
    }
}

/// The released app keeps one Markdown transcript per day. This build writes none.
enum AgentTranscriptLog {
    static let folderDefaultsKey = "voiceAgentTranscriptFolder"

    static func defaultFolder() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Echo One Agent")
    }

    static func folder() -> URL {
        if let path = UserDefaults.standard.string(forKey: folderDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultFolder()
    }

    static func fileURL(for date: Date, in folder: URL = folder()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return folder.appendingPathComponent(formatter.string(from: date) + ".md")
    }

    static func append(command: String, reply: String, model: String, access: String, actions: [String] = [],
                       usage: VoiceAgent.AgentUsage? = nil) {}

    struct WeekSummary: Equatable {
        let commands: Int
        let costUSD: Double
        let onAPIKey: Bool
        var codexCommands = 0
    }

    static func weekSummary() -> WeekSummary? { nil }

    struct Day: Identifiable, Equatable {
        var id: String { file.path }
        let file: URL
        let title: String
        let exchanges: Int
    }

    static func days() -> [Day] { [] }

    static func openInTextEdit(_ file: URL) {
        NSWorkspace.shared.open(file)
    }
}

/// The released app shows the signed-in Claude Code or Codex account here.
enum ClaudeAccount {
    enum Status {
        case checking, notInstalled, signedOut
        case signedIn(email: String, plan: String)
    }

    static func status() async -> Status { .notInstalled }
    static func codexStatus() async -> Status { .notInstalled }
    static func openSignIn(_ provider: VoiceAgent.Provider = .claude) {}
}
