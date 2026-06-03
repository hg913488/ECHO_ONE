import Foundation

enum RuntimeModelStatus: Equatable {
    case notLoaded
    case loading
    case downloading(progress: Double?)
    case loaded
}

struct RuntimeModelRow: Identifiable, Equatable {
    let id: String
    let name: String
    let sizeDescription: String
    let isSelected: Bool
    let status: RuntimeModelStatus
}

enum RuntimeModelInventory {
    static func rows(
        selectedSpeechModelName: String,
        activeSpeechModelName: String,
        speechModelState: ModelManagerState,
        speechDownloadProgress: Double?,
        cachedSpeechModelNames: Set<String>,
        cleanupState: CleanupModelState,
        selectedCleanupModelKind: LocalCleanupModelKind,
        cachedCleanupKinds: Set<LocalCleanupModelKind>
    ) -> [RuntimeModelRow] {
        let speechRows = ModelManager.availableModels.map { model in
            RuntimeModelRow(
                id: model.name,
                name: model.statusName,
                sizeDescription: model.sizeDescription,
                isSelected: model.name == selectedSpeechModelName,
                status: statusForSpeechModel(
                    named: model.name,
                    activeSpeechModelName: activeSpeechModelName,
                    speechModelState: speechModelState,
                    speechDownloadProgress: speechDownloadProgress,
                    cachedSpeechModelNames: cachedSpeechModelNames
                )
            )
        }

        let cleanupRows = TextCleanupManager.cleanupModels.map { model in
            RuntimeModelRow(
                id: "cleanup-\(model.fileName)",
                name: model.displayName,
                sizeDescription: model.sizeDescription,
                isSelected: model.kind == selectedCleanupModelKind,
                status: statusForCleanupModel(
                    kind: model.kind,
                    cleanupState: cleanupState,
                    cachedCleanupKinds: cachedCleanupKinds
                )
            )
        }

        return speechRows + cleanupRows
    }

    static func activeDownloadText(rows: [RuntimeModelRow]) -> String? {
        guard let row = rows.first(where: \.isDownloading) else {
            return nil
        }

        switch row.status {
        case .downloading(let progress?):
            let pct = Int(progress * 100)
            return "Downloading \(row.name) (\(pct)%)..."
        case .downloading(nil):
            return "Preparing \(row.name)..."
        case .loading, .loaded, .notLoaded:
            return nil
        }
    }

    private static func statusForSpeechModel(
        named modelName: String,
        activeSpeechModelName: String,
        speechModelState: ModelManagerState,
        speechDownloadProgress: Double?,
        cachedSpeechModelNames: Set<String>
    ) -> RuntimeModelStatus {
        if speechModelState == .loading && modelName == activeSpeechModelName {
            if cachedSpeechModelNames.contains(modelName) {
                return .loading
            }
            return .downloading(progress: speechDownloadProgress)
        }

        return cachedSpeechModelNames.contains(modelName) ? .loaded : .notLoaded
    }

    private static func statusForCleanupModel(
        kind: LocalCleanupModelKind,
        cleanupState: CleanupModelState,
        cachedCleanupKinds: Set<LocalCleanupModelKind>
    ) -> RuntimeModelStatus {
        if case let .downloading(activeKind, progress) = cleanupState, activeKind == kind {
            return .downloading(progress: progress)
        }

        if case let .loadingModel(activeKind) = cleanupState, activeKind == kind {
            return .loading
        }

        if cachedCleanupKinds.contains(kind) {
            return .loaded
        }

        return .notLoaded
    }
}

private extension RuntimeModelRow {
    var isDownloading: Bool {
        if case .downloading = status {
            return true
        }
        return false
    }
}
