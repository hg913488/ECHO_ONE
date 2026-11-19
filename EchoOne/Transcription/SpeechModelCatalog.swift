import Foundation

enum SpeechBackendKind: Equatable {
    case whisperKit
    case fluidAudio
}

enum FluidAudioModelVariant: Equatable {
    case parakeetUltra
}

struct SpeechModelDescriptor: Identifiable, Equatable {
    let name: String
    let pickerTitle: String
    let variantName: String
    let sizeDescription: String
    let backend: SpeechBackendKind
    let cachePathComponents: [String]
    let fluidAudioVariant: FluidAudioModelVariant?

    var id: String { name }

    var pickerLabel: String {
        "\(pickerTitle) (\(variantName) — \(sizeDescription))"
    }

    var statusName: String {
        switch backend {
        case .whisperKit:
            "Whisper \(variantName) (\(pickerTitle.lowercased()))"
        case .fluidAudio:
            "\(pickerTitle) (\(variantName.lowercased()))"
        }
    }

    var supportsSpeakerFiltering: Bool {
        // Speaker filtering uses a separate diarization pipeline, so any
        // FluidAudio-backed ASR model can participate in filtering.
        backend == .fluidAudio
    }
}

enum SpeechModelCatalog {
    static let parakeetUltra = SpeechModelDescriptor(
        name: "fluid_parakeet-ultra",
        pickerTitle: "Parakeet Ultra",
        variantName: "25 languages",
        sizeDescription: "~630 MB",
        backend: .fluidAudio,
        cachePathComponents: ["FluidInference", "parakeet-ultra-coreml"],
        fluidAudioVariant: .parakeetUltra
    )

    static let availableModels: [SpeechModelDescriptor] = [
        parakeetUltra,
    ]

    static let defaultModelID = parakeetUltra.id

    static func model(named name: String) -> SpeechModelDescriptor? {
        availableModels.first { $0.name == name }
    }

    /// Maps a stored model ID onto one the catalog still offers, so a removed
    /// model (e.g. Qwen3-ASR) falls back to the default instead of failing to load.
    static func resolvedModelID(_ storedID: String) -> String {
        model(named: storedID) == nil ? defaultModelID : storedID
    }
}
