import Foundation

enum CleanupModelProbeThinkingMode: String, CaseIterable, Equatable, Sendable {
    case none
    case suppressed
    case enabled
}

struct CleanupModelProbeRawResult: Equatable, Sendable {
    let modelKind: LocalCleanupModelKind
    let modelDisplayName: String
    let rawOutput: String
    let elapsed: TimeInterval
}

struct CleanupModelProbeTranscript: Equatable, Sendable {
    let modelKind: LocalCleanupModelKind
    let modelDisplayName: String
    let thinkingMode: CleanupModelProbeThinkingMode
    let input: String
    let modelInputText: String
    let modelInput: String
    let finalPrompt: String
    let rawModelOutput: String
    let sanitizedOutput: String
    let finalOutput: String
    let elapsed: TimeInterval
}

enum CleanupModelProbeError: Error, LocalizedError {
    case modelUnavailable(LocalCleanupModelKind)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let modelKind):
            return "Cleanup model \(modelKind) is not loaded."
        }
    }
}
