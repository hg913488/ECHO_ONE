import XCTest
import Combine
@testable import EchoOne

@MainActor
final class TextCleanupManagerTests: XCTestCase {
    actor ProbeConcurrencyHarness {
        private var isRunning = false

        func run(text: String) async -> CleanupModelProbeRawResult {
            if isRunning {
                return CleanupModelProbeRawResult(
                    modelKind: .qwen35_2b_q4_k_m,
                    modelDisplayName: TextCleanupManager.recommendedFastModel.displayName,
                    rawOutput: "",
                    elapsed: 0
                )
            }

            isRunning = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            isRunning = false

            return CleanupModelProbeRawResult(
                modelKind: .qwen35_2b_q4_k_m,
                modelDisplayName: TextCleanupManager.recommendedFastModel.displayName,
                rawOutput: text,
                elapsed: 0.05
            )
        }
    }

    func testCleanupModelCatalogIncludesVeryFastFastAndFullQwenModels() {
        XCTAssertEqual(
            TextCleanupManager.cleanupModels.map(\.kind),
            [
                .qwen35_0_8b_q4_k_m,
                .qwen35_2b_q4_k_m,
                .qwen35_4b_q4_k_m,
            ]
        )
        XCTAssertEqual(
            TextCleanupManager.cleanupModels.map(\.displayName),
            [
                "Qwen 3.5 0.8B Q4_K_M (Very fast)",
                "Qwen 3.5 2B Q4_K_M (Fast)",
                "Qwen 3.5 4B Q4_K_M (Full)",
            ]
        )
        XCTAssertEqual(
            TextCleanupManager.recommendedFullModel.fileName,
            "Qwen3.5-4B-Q4_K_M.gguf"
        )
    }

    func testDefaultSelectionUsesFastModel() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let manager = TextCleanupManager(
            defaults: defaults,
            cleanupModelAvailabilityOverrides: [
                .qwen35_2b_q4_k_m: true
            ]
        )

        XCTAssertEqual(manager.selectedCleanupModelKind, .qwen35_2b_q4_k_m)
        XCTAssertEqual(
            manager.selectedModelKind(wordCount: 4, isQuestion: false),
            .qwen35_2b_q4_k_m
        )
    }

    func testSelectedCleanupModelPersistsConcreteModelChoice() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let manager = TextCleanupManager(
            defaults: defaults,
            cleanupModelAvailabilityOverrides: [
                .qwen35_0_8b_q4_k_m: true
            ]
        )
        manager.selectedCleanupModelKind = .qwen35_0_8b_q4_k_m

        let restored = TextCleanupManager(
            defaults: defaults,
            cleanupModelAvailabilityOverrides: [
                .qwen35_0_8b_q4_k_m: true
            ]
        )

        XCTAssertEqual(restored.selectedCleanupModelKind, .qwen35_0_8b_q4_k_m)
    }

    func testSelectedCleanupModelReturnsChosenModelWhenReady() {
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_0_8b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_0_8b_q4_k_m: true
            ]
        )

        XCTAssertEqual(
            manager.selectedModelKind(wordCount: 40, isQuestion: true),
            .qwen35_0_8b_q4_k_m
        )
    }

    func testSelectedCleanupModelTreatsChosenModelAsUsableWhenAvailable() {
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_0_8b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_0_8b_q4_k_m: true
            ]
        )

        XCTAssertTrue(manager.hasUsableModelForCurrentPolicy)
    }

    func testSelectedCleanupModelRequiresChosenModelToBeUsable() {
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_0_8b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_2b_q4_k_m: true
            ]
        )

        XCTAssertFalse(manager.hasUsableModelForCurrentPolicy)
    }

    func testCleanupSuppressesThinkingForProductionCleanupCalls() async throws {
        var capturedThinkingMode: CleanupModelProbeThinkingMode?
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_4b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_4b_q4_k_m: true
            ],
            probeExecutionOverride: { _, _, _, thinkingMode in
                capturedThinkingMode = thinkingMode
                return CleanupModelProbeRawResult(
                    modelKind: .qwen35_4b_q4_k_m,
                    modelDisplayName: TextCleanupManager.recommendedFullModel.displayName,
                    rawOutput: "That worked really well.",
                    elapsed: 0.01
                )
            }
        )

        let result = try await manager.clean(text: "That worked really well.", prompt: "unused prompt")

        XCTAssertEqual(result, "That worked really well.")
        XCTAssertEqual(capturedThinkingMode, .suppressed)
    }

    func testShutdownBackendCallsOverride() {
        var shutdownCount = 0
        let manager = TextCleanupManager(
            backendShutdownOverride: {
                shutdownCount += 1
            }
        )

        manager.shutdownBackend()
        manager.shutdownBackend()

        XCTAssertEqual(shutdownCount, 2)
    }

    func testCleanupSerializesOverlappingRequests() async throws {
        let harness = ProbeConcurrencyHarness()
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_4b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_4b_q4_k_m: true
            ],
            probeExecutionOverride: { text, _, _, _ in
                await harness.run(text: text)
            }
        )

        async let first = manager.clean(text: "first", prompt: "unused")
        async let second = manager.clean(text: "second", prompt: "unused")

        let results = try await [first, second]

        XCTAssertEqual(results, ["first", "second"])
    }

    func testCleanupThrowsUnavailableWhenSelectedModelIsMissing() async {
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_2b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_4b_q4_k_m: true
            ]
        )

        await XCTAssertThrowsErrorAsync(try await manager.clean(text: "hello", prompt: "unused")) { error in
            XCTAssertEqual(error as? CleanupBackendError, .unavailable)
        }
    }

    func testCleanupThrowsUnusableOutputWhenModelReturnsPlaceholder() async {
        let manager = TextCleanupManager(
            selectedCleanupModelKind: .qwen35_2b_q4_k_m,
            cleanupModelAvailabilityOverrides: [
                .qwen35_2b_q4_k_m: true
            ],
            probeExecutionOverride: { _, _, _, _ in
                CleanupModelProbeRawResult(
                    modelKind: .qwen35_2b_q4_k_m,
                    modelDisplayName: TextCleanupManager.recommendedFastModel.displayName,
                    rawOutput: "...",
                    elapsed: 0.01
                )
            }
        )

        await XCTAssertThrowsErrorAsync(try await manager.clean(text: "hello", prompt: "unused")) { error in
            XCTAssertEqual(
                error as? CleanupBackendError,
                .unusableOutput(rawOutput: "...")
            )
        }
    }

    func testDeleteCachedModelNotifiesObserversForInventoryRefresh() {
        let manager = TextCleanupManager()
        let expectation = expectation(description: "cleanup manager publishes cache deletion")
        var cancellable: AnyCancellable? = manager.objectWillChange.sink {
            expectation.fulfill()
        }

        manager.deleteCachedModel(kind: .qwen35_0_8b_q4_k_m)

        wait(for: [expectation], timeout: 1.0)
        withExtendedLifetime(cancellable) {}
        cancellable = nil
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message().isEmpty ? "Expected error to be thrown." : message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

@MainActor
final class MeetingSummaryGeneratorTests: XCTestCase {
    private func makeTranscript(lineCount: Int, notes: String = "") -> MeetingTranscript {
        let transcript = MeetingTranscript(meetingName: "Planning")
        transcript.notes = notes
        for index in 0..<lineCount {
            transcript.appendSegment(
                TranscriptSegment(
                    id: UUID(),
                    speaker: index.isMultiple(of: 2) ? .me : .remote(name: "Sam"),
                    startTime: TimeInterval(index * 7),
                    endTime: TimeInterval(index * 7 + 6),
                    text: "We agreed the launch moves to the fourteenth and Sam owns the pricing page copy."
                )
            )
        }
        return transcript
    }

    func testShortMeetingSendsSummaryPromptAsSystemPrompt() async throws {
        var calls: [(text: String, systemPrompt: String)] = []
        let generator = MeetingSummaryGenerator(contextTokenLimit: 2048) { text, systemPrompt in
            calls.append((text, systemPrompt))
            return "### Launch\n- Moves to the fourteenth"
        }

        let summary = try await generator.generateSummary(
            transcript: makeTranscript(lineCount: 3, notes: "Pricing page"),
            finalPrompt: "FINAL PROMPT"
        )

        XCTAssertEqual(summary, "### Launch\n- Moves to the fourteenth")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].systemPrompt, "FINAL PROMPT")
        XCTAssertFalse(calls[0].text.contains("FINAL PROMPT"))
        XCTAssertTrue(calls[0].text.contains("User's notes during the meeting:\n\nPricing page"))
        XCTAssertTrue(calls[0].text.contains("[00:07] Sam: We agreed"))
    }

    func testLongMeetingKeepsEveryCallInsideTheContextWindow() async throws {
        let contextTokenLimit = 2048
        let chunkPrompt = MeetingSummaryGenerator.defaultPrompt
        let finalPrompt = MeetingSummaryGenerator.finalSummaryPrompt
        var calls: [(text: String, systemPrompt: String)] = []
        let generator = MeetingSummaryGenerator(contextTokenLimit: contextTokenLimit) { text, systemPrompt in
            calls.append((text, systemPrompt))
            return String(repeating: "- Launch moves to the fourteenth; Sam owns pricing copy.\n", count: 12)
        }

        let summary = try await generator.generateSummary(transcript: makeTranscript(lineCount: 400))

        XCTAssertNotNil(summary)
        XCTAssertGreaterThan(calls.count, 3)
        XCTAssertEqual(calls.last?.systemPrompt, finalPrompt)
        XCTAssertTrue(calls.dropLast().allSatisfy { $0.systemPrompt == chunkPrompt })
        for call in calls {
            let budget = MeetingSummaryGenerator.inputCharacterBudget(
                contextTokenLimit: contextTokenLimit,
                prompt: call.systemPrompt
            )
            XCTAssertLessThanOrEqual(call.text.count, budget)
        }
    }

    func testInputBudgetLeavesRoomForTheAnswer() {
        let small = MeetingSummaryGenerator.inputCharacterBudget(
            contextTokenLimit: 2048,
            prompt: MeetingSummaryGenerator.finalSummaryPrompt
        )
        let promptTokens = MeetingSummaryGenerator.finalSummaryPrompt.count / MeetingSummaryGenerator.charactersPerToken
        XCTAssertLessThan(small / MeetingSummaryGenerator.charactersPerToken + promptTokens, 2048 - 384)

        let large = MeetingSummaryGenerator.inputCharacterBudget(contextTokenLimit: 32768, prompt: "p")
        XCTAssertEqual(large, MeetingSummaryGenerator.maxInputCharacters)
    }

    func testSplitIntoChunksHardSplitsOverlongLines() {
        let text = String(repeating: "a", count: 250) + "\nshort line"
        let chunks = MeetingSummaryGenerator.splitIntoChunks(text, limit: 100)

        XCTAssertTrue(chunks.allSatisfy { $0.count <= 100 })
        XCTAssertEqual(chunks.joined().replacingOccurrences(of: "\n", with: "").count, 250 + "short line".count)
    }

    func testSummaryErrorsPropagate() async {
        let generator = MeetingSummaryGenerator(contextTokenLimit: 2048) { _, _ in
            throw CleanupBackendError.unavailable
        }

        do {
            _ = try await generator.generateSummary(transcript: makeTranscript(lineCount: 2))
            XCTFail("Expected the cleanup error to propagate")
        } catch {
            XCTAssertEqual(error as? CleanupBackendError, .unavailable)
        }
    }
}
