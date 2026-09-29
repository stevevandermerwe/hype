import Foundation
import CryptoKit

/// A copy of a deck with unsaved edits, kept so a crash or an unsaved quit doesn't
/// lose them. `path` is the file it was a copy of; nil for a deck never saved.
public struct RecoverySnapshot: Identifiable, Equatable, Sendable {
    public var key: String
    public var path: String?
    public var title: String
    public var savedAt: Date
    public var source: String
    public var id: String { key }
}

private struct SnapshotFile: Codable {
    var path: String?
    var title: String
    var savedAt: Date
    var source: String
}

/// Where recovery snapshots live: one `<key>.json` per deck in a folder
/// (`~/Library/Application Support/Hype/Recovery` by default; the Qt app keeps
/// the same kind of copy under its state directory). A snapshot is replaced as
/// you keep editing, removed when you save, and dropped after 30 days.
public final class RecoveryStore: @unchecked Sendable {
    public static let shared = RecoveryStore(directory: RecoveryStore.defaultDirectory)

    /// The default folder, or the one named by the `HYPE_RECOVERY_DIR` environment
    /// variable (for tests and scripts).
    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["HYPE_RECOVERY_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hype/Recovery", isDirectory: true)
    }

    private static let retention: TimeInterval = 30 * 86_400

    public let directory: URL
    private let now: () -> Date

    public init(directory: URL, now: @escaping () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// The key for a deck saved at `path`: stable, and safe as a filename.
    public static func key(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return "file-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The key for a deck that has no file yet, from an id unique to the session.
    public static func untitledKey(_ id: String) -> String {
        "untitled-" + String(id.filter { $0.isLetter || $0.isNumber || $0 == "-" })
    }

    private func file(for key: String) -> URL {
        directory.appendingPathComponent(String(key.filter { $0.isLetter || $0.isNumber || $0 == "-" }) + ".json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes (or replaces) the snapshot for `key`.
    public func snapshot(key: String, source: String, path: String?, title: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = SnapshotFile(path: path, title: title, savedAt: now(), source: source)
        try Self.encoder.encode(contents).write(to: file(for: key), options: .atomic)
    }

    public func discard(key: String) {
        try? FileManager.default.removeItem(at: file(for: key))
    }

    /// Snapshots worth offering to recover, newest first. Ones older than 30 days,
    /// unreadable ones, and ones identical to the file they were a copy of
    /// (nothing would be recovered) are skipped and cleaned up.
    public func pending() -> [RecoverySnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var found: [RecoverySnapshot] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let stored = try? Self.decoder.decode(SnapshotFile.self, from: data) else { continue }
            let stale = now().timeIntervalSince(stored.savedAt) > Self.retention
            let unchanged = stored.path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } == stored.source
            if stale || unchanged {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            found.append(RecoverySnapshot(key: url.deletingPathExtension().lastPathComponent, path: stored.path,
                                          title: stored.title, savedAt: stored.savedAt, source: stored.source))
        }
        return found.sorted { $0.savedAt > $1.savedAt }
    }
}

/// Timestamped copies of a presentation, made just before a save overwrites it, in
/// a `.hype-backups` folder beside it (like the Qt app's), so an older version is
/// never more than a Finder copy away. The newest ten are kept.
public enum Backups {
    /// Copies the file at `path` into `.hype-backups` as `<name>-<time>-<n>.md`,
    /// unless it doesn't exist or already equals `newContent`. Returns the backup's path.
    @discardableResult
    public static func backupBeforeOverwriting(path: String, newContent: String, keep: Int = 10, now: Date = Date()) -> String? {
        guard let existing = try? String(contentsOfFile: path, encoding: .utf8), existing != newContent else { return nil }
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent().appendingPathComponent(".hype-backups", isDirectory: true)
        let base = url.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var counter = 0
            var target = folder.appendingPathComponent(String(format: "%@-%@-%02d.md", base, stamp, counter))
            while FileManager.default.fileExists(atPath: target.path) {
                counter += 1
                target = folder.appendingPathComponent(String(format: "%@-%@-%02d.md", base, stamp, counter))
            }
            try existing.write(to: target, atomically: true, encoding: .utf8)
            prune(folder, base: base, keep: keep)
            return target.path
        } catch {
            return nil // A failed backup must never stop the save itself.
        }
    }

    private static func prune(_ folder: URL, base: String, keep: Int) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix(base + "-") && $0.hasSuffix(".md") }
            .sorted()
        for name in names.dropLast(max(0, keep)) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
