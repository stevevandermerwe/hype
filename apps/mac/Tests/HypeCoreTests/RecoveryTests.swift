import XCTest
@testable import HypeCore

/// Recovery snapshots (kept while you have unsaved edits, so a crash or a quit
/// doesn't lose them) and timestamped backups (kept before a save overwrites a file).
@MainActor
final class RecoveryTests: XCTestCase {
    private var directory: URL!
    private var store: RecoveryStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hype-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RecoveryStore(directory: directory.appendingPathComponent("snapshots"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func writeFile(_ name: String, _ text: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: Snapshots

    func testASnapshotIsListedWithItsDetailsAndSurvivesUnicode() throws {
        let path = try writeFile("talk.md", "# Old\n")
        try store.snapshot(key: RecoveryStore.key(forPath: path), source: "# New é😀\n", path: path, title: "Talk")
        let found = store.pending()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].source, "# New é😀\n")
        XCTAssertEqual(found[0].path, path)
        XCTAssertEqual(found[0].title, "Talk")
        XCTAssertLessThan(abs(found[0].savedAt.timeIntervalSinceNow), 5)
    }

    func testKeysAreStablePerFileAndDistinctBetweenFilesAndUntitledDecks() {
        XCTAssertEqual(RecoveryStore.key(forPath: "/a/b.md"), RecoveryStore.key(forPath: "/a/b.md"))
        XCTAssertNotEqual(RecoveryStore.key(forPath: "/a/b.md"), RecoveryStore.key(forPath: "/a/c.md"))
        XCTAssertNotEqual(RecoveryStore.untitledKey("one"), RecoveryStore.untitledKey("two"))
        XCTAssertTrue(RecoveryStore.key(forPath: "/a/../../etc/x").allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "safe as a filename")
    }

    func testANewSnapshotReplacesTheOldOneForTheSameKeyAndDiscardRemovesIt() throws {
        let key = RecoveryStore.untitledKey("session")
        try store.snapshot(key: key, source: "one", path: nil, title: "Untitled")
        try store.snapshot(key: key, source: "two", path: nil, title: "Untitled")
        XCTAssertEqual(store.pending().map(\.source), ["two"])
        store.discard(key: key)
        XCTAssertTrue(store.pending().isEmpty)
        store.discard(key: key) // discarding again is harmless
    }

    func testNewestSnapshotsComeFirst() throws {
        var clock = Date(timeIntervalSinceNow: -100)
        let ticking = RecoveryStore(directory: directory.appendingPathComponent("snapshots"), now: { defer { clock += 10 }; return clock })
        try ticking.snapshot(key: "a", source: "A", path: nil, title: "A")
        try ticking.snapshot(key: "b", source: "B", path: nil, title: "B")
        XCTAssertEqual(store.pending().map(\.title), ["B", "A"])
    }

    func testSnapshotsAlreadyMatchingTheirFileOnDiskAreNotOffered() throws {
        let path = try writeFile("same.md", "# Same\n")
        try store.snapshot(key: RecoveryStore.key(forPath: path), source: "# Same\n", path: path, title: "Same")
        XCTAssertTrue(store.pending().isEmpty, "nothing would be recovered")
        XCTAssertTrue(store.pending().isEmpty)
    }

    func testOldSnapshotsAndDamagedFilesAreDropped() throws {
        let old = RecoveryStore(directory: directory.appendingPathComponent("snapshots"), now: { Date(timeIntervalSinceNow: -40 * 86_400) })
        try old.snapshot(key: "old", source: "stale", path: nil, title: "Old")
        try store.snapshot(key: "fresh", source: "fresh", path: nil, title: "Fresh")
        try "not json".write(to: directory.appendingPathComponent("snapshots/broken.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.pending().map(\.title), ["Fresh"])
    }

    func testAMissingFolderMeansNothingToRecover() {
        XCTAssertTrue(RecoveryStore(directory: directory.appendingPathComponent("nope")).pending().isEmpty)
    }

    // MARK: Backups

    func testOverwritingADifferentFileKeepsATimestampedBackupBesideIt() throws {
        let path = try writeFile("deck.md", "# Before\n")
        let backup = try XCTUnwrap(Backups.backupBeforeOverwriting(path: path, newContent: "# After\n"))
        XCTAssertTrue(backup.contains("/.hype-backups/deck-"), backup)
        XCTAssertEqual(try String(contentsOfFile: backup, encoding: .utf8), "# Before\n")
    }

    func testNoBackupWhenTheFileIsMissingOrUnchanged() throws {
        XCTAssertNil(Backups.backupBeforeOverwriting(path: directory.appendingPathComponent("new.md").path, newContent: "x"))
        let path = try writeFile("same.md", "# Same\n")
        XCTAssertNil(Backups.backupBeforeOverwriting(path: path, newContent: "# Same\n"))
    }

    func testOnlyTheNewestBackupsAreKept() throws {
        let path = try writeFile("deck.md", "v0")
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        for version in 1...5 {
            _ = Backups.backupBeforeOverwriting(path: path, newContent: "v\(version)", keep: 3, now: clock)
            try "v\(version)".write(toFile: path, atomically: true, encoding: .utf8)
            clock += 60
        }
        let folder = directory.appendingPathComponent(".hype-backups")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(names.last!), encoding: .utf8), "v4", "the newest holds the version before the last save")
    }

    func testTwoBackupsInTheSameSecondDoNotClash() throws {
        let path = try writeFile("deck.md", "one")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = Backups.backupBeforeOverwriting(path: path, newContent: "two", now: now)
        let second = Backups.backupBeforeOverwriting(path: path, newContent: "three", now: now)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
    }

    // MARK: In a deck

    func testAnEditedDeckWritesARecoverySnapshotAndSavingClearsIt() throws {
        let deck = DeckModel(source: "# One\n", recovery: store)
        deck.editSlide("# Changed")
        deck.flushRecoverySnapshot()
        XCTAssertEqual(store.pending().map(\.source), ["# Changed\n"])
        XCTAssertEqual(store.pending().first?.title, "Untitled")

        let path = directory.appendingPathComponent("saved.md").path
        XCTAssertTrue(deck.savePath(path))
        XCTAssertTrue(store.pending().isEmpty, "saving makes the snapshot unnecessary")
    }

    func testACleanDeckLeavesNoSnapshotAndUndoingBackToCleanRemovesIt() {
        let deck = DeckModel(source: "# One\n", recovery: store)
        deck.flushRecoverySnapshot()
        XCTAssertTrue(store.pending().isEmpty)
        deck.editSlide("# Two")
        deck.flushRecoverySnapshot()
        XCTAssertEqual(store.pending().count, 1)
        deck.undo()
        deck.flushRecoverySnapshot()
        XCTAssertTrue(store.pending().isEmpty)
    }

    func testSnapshotsAreKeptPerFileNotJustForTheOpenDeck() throws {
        let path = try writeFile("talk.md", "# Disk\n")
        let deck = DeckModel(recovery: store)
        XCTAssertTrue(deck.loadPath(path))
        deck.editSlide("# Edited")
        deck.flushRecoverySnapshot()
        XCTAssertEqual(store.pending().first?.path, path)
        XCTAssertEqual(store.pending().first?.title, "talk")
    }

    func testRestoringASnapshotBringsBackTheTextAsUnsavedChanges() throws {
        let path = try writeFile("talk.md", "# Disk\n")
        let crashed = DeckModel(recovery: store)
        _ = crashed.loadPath(path)
        crashed.editSlide("# Lost work")
        crashed.flushRecoverySnapshot()

        let relaunched = DeckModel(recovery: store)
        let snapshot = try XCTUnwrap(store.pending().first)
        relaunched.restore(snapshot)
        XCTAssertEqual(relaunched.slideText(at: 0), "# Lost work")
        XCTAssertEqual(relaunched.path, path)
        XCTAssertTrue(relaunched.dirty, "still unsaved, so it can be saved deliberately")
        XCTAssertTrue(relaunched.save())
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# Lost work\n")
        XCTAssertTrue(store.pending().isEmpty)
    }

    func testRestoringAnUntitledSnapshotHasNoFileYet() throws {
        let first = DeckModel(recovery: store)
        first.editSlide("# Never saved")
        first.flushRecoverySnapshot()
        let second = DeckModel(recovery: store)
        second.restore(try XCTUnwrap(store.pending().first))
        XCTAssertNil(second.path)
        XCTAssertEqual(second.slideText(at: 0), "# Never saved")
        XCTAssertTrue(second.dirty)
    }

    func testSavingOverAnExistingFileKeepsABackupOfTheOldVersion() throws {
        let path = try writeFile("deck.md", "# Original\n")
        let deck = DeckModel()
        _ = deck.loadPath(path)
        deck.editSlide("# Edited")
        XCTAssertTrue(deck.save())
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(".hype-backups").path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(".hype-backups/\(backups[0])"), encoding: .utf8), "# Original\n")
    }

    func testDiscardingRemovesTheCurrentDecksSnapshot() {
        let deck = DeckModel(source: "# One\n", recovery: store)
        deck.editSlide("# Two")
        deck.flushRecoverySnapshot()
        deck.discardRecoverySnapshot()
        XCTAssertTrue(store.pending().isEmpty)
    }
}
