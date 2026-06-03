import Foundation

protocol CleanupBackend: AnyObject {
    func clean(text: String, prompt: String, modelKind: LocalCleanupModelKind?) async throws -> String
}

enum CleanupBackendError: Error, Equatable {
    case unavailable
    case unusableOutput(rawOutput: String)
}
