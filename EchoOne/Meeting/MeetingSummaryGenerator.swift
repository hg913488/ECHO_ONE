import Foundation

/// Generates meeting summaries using the local LLM via chunked summarization.
///
/// Strategy: The transcript is split into chunks sized to the model's context window.
/// Each chunk is summarized into bullet points. The bullet points are reduced until
/// they fit one window, then combined into a final summary.
@MainActor
final class MeetingSummaryGenerator {
    /// Runs the LLM with `systemPrompt` as the system prompt and `text` as the user input.
    typealias LLMRunner = @MainActor (_ text: String, _ systemPrompt: String) async throws -> String

    private let runner: LLMRunner
    private let contextTokenLimit: Int

    /// Conservative: timestamps, names and numbers tokenize denser than prose.
    static let charactersPerToken = 3
    /// Tokens for the chat template and special tokens around the prompt.
    static let templateTokenOverhead = 64
    /// Upper bound per call so even a large-context model answers within the timeout.
    static let maxInputCharacters = 12_000
    static let minInputCharacters = 600

    static let defaultPrompt = """
    Summarize the following meeting excerpt. Output concise bullet points organized by topic. \
    Include key facts, decisions, numbers, names, and dates. Be brief.
    """

    static let finalSummaryPrompt = """
    You are summarizing a meeting. You will receive a transcript and optionally the user's own notes \
    taken during the meeting. Read both carefully, then produce a structured summary organized by topic.

    Rules:
    - If the user wrote notes, treat them as a guide — they highlight what mattered most. Ensure those topics are covered prominently and expand on them with details from the transcript.
    - Use ### headings for each major topic discussed (e.g., "### Product Update", "### Hiring Plan", "### Q3 Budget")
    - Under each topic, use concise bullet points capturing key facts, decisions, numbers, names, and dates
    - Include a "### Next Steps" section at the end with any action items or follow-ups mentioned, using checkbox format: - [ ] Task — Owner
    - If the meeting is a 1:1 or introductory call, organize by the person/company discussed and what was learned
    - If the meeting is a group discussion or brainstorm, organize by the themes that emerged
    - Do NOT use generic headings like "Discussion Points" or "Key Takeaways" — use specific topic names from the actual conversation
    - Do NOT include filler, pleasantries, or off-topic chatter
    - Keep bullets factual and specific
    - Write in present tense for facts, past tense for what happened
    """

    init(contextTokenLimit: Int, runner: @escaping LLMRunner) {
        self.contextTokenLimit = contextTokenLimit
        self.runner = runner
    }

    convenience init(cleanupManager: TextCleanupManager) {
        let modelKind = cleanupManager.summaryModelKind
        self.init(contextTokenLimit: cleanupManager.maxTokenCount(for: modelKind)) { text, systemPrompt in
            try await cleanupManager.summarize(text: text, systemPrompt: systemPrompt, modelKind: modelKind)
        }
    }

    /// Characters of user input that fit beside `prompt` while leaving room for the answer.
    static func inputCharacterBudget(contextTokenLimit: Int, prompt: String) -> Int {
        let outputReserve = min(1024, max(384, contextTokenLimit / 3))
        let promptTokens = prompt.count / charactersPerToken + 1
        let inputTokens = contextTokenLimit - outputReserve - templateTokenOverhead - promptTokens
        return min(maxInputCharacters, max(minInputCharacters, inputTokens * charactersPerToken))
    }

    /// Generate a full summary for a completed meeting transcript.
    /// Returns the summary as markdown text, or nil if generation fails.
    func generateSummary(
        transcript: MeetingTranscript,
        chunkPrompt: String = MeetingSummaryGenerator.defaultPrompt,
        finalPrompt: String = MeetingSummaryGenerator.finalSummaryPrompt
    ) async throws -> String? {
        let segments = transcript.segments
        guard !segments.isEmpty else { return nil }

        let fullText = segments.map { segment in
            "[\(segment.formattedTimestamp)] \(segment.speaker.displayName): \(segment.text)"
        }.joined(separator: "\n")

        let chunkBudget = Self.inputCharacterBudget(contextTokenLimit: contextTokenLimit, prompt: chunkPrompt)
        let finalBudget = Self.inputCharacterBudget(contextTokenLimit: contextTokenLimit, prompt: finalPrompt)

        // User notes guide the summary, but may not crowd out the transcript.
        let notesText = String(
            transcript.notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(finalBudget / 3)
        )
        let notesPrefix = notesText.isEmpty ? "" : "User's notes during the meeting:\n\n\(notesText)\n\n"
        let finalContentBudget = max(Self.minInputCharacters / 2, finalBudget - notesPrefix.count - 40)

        if fullText.count <= finalContentBudget {
            // Short meeting — summarize directly with the final prompt
            return try await runLLM(text: "\(notesPrefix)Meeting transcript:\n\n\(fullText)", prompt: finalPrompt)
        }

        // Map: summarize each chunk
        let chunks = Self.splitIntoChunks(fullText, limit: chunkBudget - 60)
        var parts: [String] = []
        for (i, chunk) in chunks.enumerated() {
            let input = "Meeting transcript (part \(i + 1) of \(chunks.count)):\n\n\(chunk)"
            if let summary = try await runLLM(text: input, prompt: chunkPrompt) {
                parts.append(summary)
            }
        }
        guard !parts.isEmpty else { return nil }

        // Reduce: merge part summaries until they fit the final window
        var combined = Self.combine(parts)
        while combined.count > finalContentBudget && parts.count > 1 {
            let groups = Self.splitIntoChunks(combined, limit: chunkBudget - 60)
            guard groups.count < parts.count else { break }
            var reduced: [String] = []
            for group in groups {
                if let summary = try await runLLM(text: "Meeting notes so far:\n\n\(group)", prompt: chunkPrompt) {
                    reduced.append(summary)
                }
            }
            guard !reduced.isEmpty else { break }
            parts = reduced
            combined = Self.combine(parts)
        }

        let finalInput = "\(notesPrefix)Combined meeting notes:\n\n\(combined.prefix(finalContentBudget))"
        return try await runLLM(text: finalInput, prompt: finalPrompt)
    }

    // MARK: - Private

    private static func combine(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.enumerated().map { i, s in
            "Part \(i + 1):\n\(s)"
        }.joined(separator: "\n\n")
    }

    /// Splits on line boundaries into chunks of at most `limit` characters.
    /// A single line longer than `limit` is hard-split.
    static func splitIntoChunks(_ text: String, limit: Int) -> [String] {
        let limit = max(1, limit)
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var current = ""

        for var line in text.components(separatedBy: "\n") {
            while line.count > limit {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                chunks.append(String(line.prefix(limit)))
                line = String(line.dropFirst(limit))
            }
            if current.count + line.count + 1 > limit && !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func runLLM(text: String, prompt: String) async throws -> String? {
        let result = try await runner(text, prompt)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
