import Foundation

struct TranscriptionLabSpeakerProfile: Codable, Equatable {
    let entryID: UUID
    let speakerID: String
    var displayName: String
    var isMe: Bool
    var evidenceTranscript: String
}

final class TranscriptionLabSpeakerProfileStore {
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
    }

    func loadProfiles(for entryID: UUID) throws -> [TranscriptionLabSpeakerProfile] {
        let entryURL = profilesURL(for: entryID)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            return []
        }

        let data = try Data(contentsOf: entryURL)
        let profiles = try decoder.decode([TranscriptionLabSpeakerProfile].self, from: data)
        return profiles.sorted { lhs, rhs in
            lhs.speakerID.localizedStandardCompare(rhs.speakerID) == .orderedAscending
        }
    }

    func loadAllProfiles() throws -> [TranscriptionLabSpeakerProfile] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let profileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "json" }

        var profiles: [TranscriptionLabSpeakerProfile] = []
        for profileURL in profileURLs {
            let data = try Data(contentsOf: profileURL)
            profiles.append(contentsOf: try decoder.decode([TranscriptionLabSpeakerProfile].self, from: data))
        }

        return profiles.sorted { lhs, rhs in
            if lhs.entryID != rhs.entryID {
                return lhs.entryID.uuidString < rhs.entryID.uuidString
            }
            return lhs.speakerID.localizedStandardCompare(rhs.speakerID) == .orderedAscending
        }
    }

    func upsert(_ profile: TranscriptionLabSpeakerProfile) throws {
        var profiles = try loadProfiles(for: profile.entryID)
        profiles.removeAll { $0.speakerID == profile.speakerID }
        profiles.append(profile)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(profiles)
        try data.write(to: profilesURL(for: profile.entryID), options: .atomic)
    }

    private func profilesURL(for entryID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(entryID.uuidString).json")
    }

    private static var defaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("EchoOne", isDirectory: true)
            .appendingPathComponent("transcription-lab-speaker-profiles", isDirectory: true)
    }
}
