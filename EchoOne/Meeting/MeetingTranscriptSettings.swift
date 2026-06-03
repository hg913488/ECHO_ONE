import Foundation

/// Helpers for persisting meeting transcript settings.
enum MeetingTranscriptSettings {
    private static let saveDirectoryKey = "meetingTranscriptSaveDirectory"

    /// Returns the default save directory: ~/Documents/Echo One Meetings/
    static func defaultSaveDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Echo One Meetings")
    }

    /// Load the user-chosen save directory, or nil to use the default.
    static func loadSaveDirectory() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: saveDirectoryKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            // Re-save fresh bookmark
            saveSaveDirectory(url)
        }
        return url
    }

    /// Persist the user-chosen save directory as a security-scoped bookmark.
    static func saveSaveDirectory(_ url: URL) {
        guard let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            // Fallback: just save the path if bookmark fails (non-sandboxed app)
            UserDefaults.standard.set(url.path, forKey: saveDirectoryKey + "Path")
            return
        }
        UserDefaults.standard.set(bookmarkData, forKey: saveDirectoryKey)
    }

    /// Returns the effective save directory (user-chosen or default).
    static func effectiveSaveDirectory() -> URL {
        return loadSaveDirectory() ?? defaultSaveDirectory()
    }
}
