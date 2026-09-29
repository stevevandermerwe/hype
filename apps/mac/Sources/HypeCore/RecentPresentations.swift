import Foundation

/// One presentation the start page can offer to reopen: the file's path,
/// a display name (the containing folder's name for a generic
/// `presentation.md`, matching how AI-generated decks are named), and the
/// folder shown beneath it.
public struct RecentPresentation: Identifiable, Sendable {
    public var path: String
    public var name: String
    public var folder: String
    public var id: String { path }
}

/// Tracks the last few opened presentations in `UserDefaults`, for the start
/// page's Recent list — matches the Qt app's `files/recent` (`deck.cpp`).
public enum RecentPresentations {
    private static let key = "files.recent"
    private static let maxCount = 8

    public static func record(_ path: String) {
        let defaults = UserDefaults.standard
        var paths = defaults.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > maxCount { paths.removeLast(paths.count - maxCount) }
        defaults.set(paths, forKey: key)
    }

    /// Files that still exist, newest first.
    public static func list() -> [RecentPresentation] {
        let fm = FileManager.default
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.compactMap { path -> RecentPresentation? in
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            let url = URL(fileURLWithPath: path)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let baseName = url.deletingPathExtension().lastPathComponent
            let isGeneric = baseName.lowercased() == "presentation" && !folderName.isEmpty
            var folder = url.deletingLastPathComponent().path
            let home = fm.homeDirectoryForCurrentUser.path
            if folder.hasPrefix(home) { folder = "~" + folder.dropFirst(home.count) }
            return RecentPresentation(path: path, name: isGeneric ? folderName : baseName, folder: folder)
        }
    }
}
