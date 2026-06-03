import Foundation

final class LocalLLMCleanupBackend: CleanupBackend {
    private let cleanupManager: TextCleaningManaging

    init(cleanupManager: TextCleaningManaging) {
        self.cleanupManager = cleanupManager
    }

    func clean(text: String, prompt: String, modelKind: LocalCleanupModelKind?) async throws -> String {
        try await cleanupManager.clean(text: text, prompt: prompt, modelKind: modelKind)
    }
}
