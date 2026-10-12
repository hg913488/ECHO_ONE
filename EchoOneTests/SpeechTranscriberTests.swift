import XCTest
@testable import EchoOne

@MainActor
final class SpeechTranscriberTests: XCTestCase {

    func testSpeechModelCatalogIncludesWhisperAndParakeetModels() {
        let ids = SpeechModelCatalog.availableModels.map(\.id)
        let backends = SpeechModelCatalog.availableModels.map(\.backend)

        XCTAssertEqual(ids, [
            "openai_whisper-tiny.en",
            "openai_whisper-small.en",
            "openai_whisper-small",
            "fluid_parakeet-v3",
            "fluid_parakeet-ultra",
        ])
        XCTAssertEqual(backends, [
            .whisperKit,
            .whisperKit,
            .whisperKit,
            .fluidAudio,
            .fluidAudio,
        ])

        XCTAssertEqual(SpeechModelCatalog.defaultModelID, "fluid_parakeet-ultra")
    }

    func testFluidAudioSpeechModelsSupportSpeakerFiltering() {
        XCTAssertFalse(SpeechModelCatalog.whisperTiny.supportsSpeakerFiltering)
        XCTAssertFalse(SpeechModelCatalog.whisperSmallEnglish.supportsSpeakerFiltering)
        XCTAssertFalse(SpeechModelCatalog.whisperSmallMultilingual.supportsSpeakerFiltering)
        XCTAssertTrue(SpeechModelCatalog.parakeetV3.supportsSpeakerFiltering)
        XCTAssertTrue(SpeechModelCatalog.parakeetUltra.supportsSpeakerFiltering)
    }

    func testParakeetUltraDescriptor() {
        let model = SpeechModelCatalog.parakeetUltra
        XCTAssertEqual(model.name, "fluid_parakeet-ultra")
        XCTAssertEqual(model.backend, .fluidAudio)
        XCTAssertEqual(model.fluidAudioVariant, .parakeetUltra)
        XCTAssertTrue(model.pickerLabel.contains("Parakeet Ultra"))
        XCTAssertTrue(model.pickerLabel.contains("~630 MB"))
    }

    func testRemovedSpeechModelResolvesToDefault() {
        XCTAssertNil(SpeechModelCatalog.model(named: "fluid_qwen3-asr-0.6b-int8"))
        XCTAssertEqual(
            SpeechModelCatalog.resolvedModelID("fluid_qwen3-asr-0.6b-int8"),
            SpeechModelCatalog.defaultModelID
        )
        XCTAssertEqual(
            SpeechModelCatalog.resolvedModelID("openai_whisper-small.en"),
            "openai_whisper-small.en"
        )
    }

    func testCustomVocabularyTermsAreTrimmedAndDeduplicated() {
        XCTAssertEqual(
            ModelManager.customVocabularyTerms(from: ["  Hightide One ", "", "hightide one", "Dayframe", "   "]),
            ["Hightide One", "Dayframe"]
        )
        XCTAssertEqual(ModelManager.customVocabularyTerms(from: []), [])
    }

    func testModelManagerDefaultModelName() {
        let manager = ModelManager()
        XCTAssertEqual(manager.modelName, "fluid_parakeet-ultra")
    }

    func testModelManagerCustomModelName() {
        let manager = ModelManager(modelName: "openai_whisper-tiny.en")
        XCTAssertEqual(manager.modelName, "openai_whisper-tiny.en")
    }

    func testModelManagerStateEnum() {
        // Verify all states are distinct
        let states: [ModelManagerState] = [.idle, .loading, .ready, .error]
        for (i, a) in states.enumerated() {
            for (j, b) in states.enumerated() {
                if i == j {
                    XCTAssertEqual(a, b)
                } else {
                    XCTAssertNotEqual(a, b)
                }
            }
        }
    }

    // MARK: - SpeechTranscriber Tests

    func testTranscriberReportsNotReadyBeforeModelLoad() {
        let manager = ModelManager()
        let transcriber = SpeechTranscriber(modelManager: manager)
        XCTAssertFalse(transcriber.isReady)
    }

    func testTranscriberEmptyAudioReturnsNil() async {
        let manager = ModelManager()
        let transcriber = SpeechTranscriber(modelManager: manager)
        let result = await transcriber.transcribe(audioBuffer: [])
        XCTAssertNil(result, "Empty audio buffer should return nil")
    }

    func testTranscriberReturnsNilWhenModelNotLoaded() async {
        let manager = ModelManager()
        let transcriber = SpeechTranscriber(modelManager: manager)
        // Non-empty buffer but model not loaded should return nil
        let silence = [Float](repeating: 0.0, count: 16000)
        let result = await transcriber.transcribe(audioBuffer: silence)
        XCTAssertNil(result, "Should return nil when model is not loaded")
    }

    // MARK: - Parakeet Ultra ModelManager Tests

    func testModelManagerLoadsParakeetUltraThroughOverride() async throws {
        var loadedDescriptors: [SpeechModelDescriptor] = []
        let manager = ModelManager(
            modelName: "fluid_parakeet-ultra",
            modelLoadOverride: { descriptor in
                loadedDescriptors.append(descriptor)
            },
            loadRetryDelayOverride: {}
        )

        await manager.loadModel()

        XCTAssertEqual(manager.state, .ready)
        XCTAssertNil(manager.error)
        XCTAssertEqual(loadedDescriptors.count, 1)
        XCTAssertEqual(loadedDescriptors.first?.name, "fluid_parakeet-ultra")
        XCTAssertEqual(loadedDescriptors.first?.fluidAudioVariant, .parakeetUltra)
    }

    func testModelManagerSurfacesParakeetUltraLoadFailure() async throws {
        struct DownloadFailed: Error {}
        let manager = ModelManager(
            modelName: "fluid_parakeet-ultra",
            modelLoadOverride: { _ in throw DownloadFailed() },
            loadRetryDelayOverride: {}
        )

        await manager.loadModel()

        XCTAssertEqual(manager.state, .error)
        XCTAssertNotNil(manager.error)
    }

    func testModelManagerSwitchesBetweenWhisperAndParakeetUltra() async throws {
        var loadedNames: [String] = []
        let manager = ModelManager(
            modelName: "openai_whisper-small.en",
            modelLoadOverride: { descriptor in
                loadedNames.append(descriptor.name)
            },
            loadRetryDelayOverride: {}
        )

        await manager.loadModel()
        XCTAssertEqual(manager.state, .ready)

        await manager.loadModel(name: "fluid_parakeet-ultra")

        XCTAssertEqual(manager.state, .ready)
        XCTAssertEqual(manager.modelName, "fluid_parakeet-ultra")
        XCTAssertEqual(loadedNames, [
            "openai_whisper-small.en",
            "fluid_parakeet-ultra",
        ])
    }
}
