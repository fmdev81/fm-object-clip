import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The fixes from the code review of PR #6: case-alias ids in a backup (#4), settings changes that must not trim
/// (#3), and a Replace by another process seen by the app (#4).
final class ReviewFixTests: XCTestCase {
    var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func history(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    func xml(_ name: String) -> Data { Data("<fmxmlsnippet><Step name=\"\(name)\"/></fmxmlsnippet>".utf8) }

    /// A backup of one store, with the ids of its entries changed to `ids` (in the order of the entries).
    func backup(_ datas: [Data], ids: [String], folder: String? = "Keep") throws -> Backup {
        let source = try HistoryStore(folder: history("source-\(UUID().uuidString)"))
        for d in datas { try source.add(d, cls: .XMSS, folder: folder) }
        var b = try source.makeBackup()
        b.items = zip(b.items, ids).map { Backup.Item(entry: $0.entry.withID($1), data: $0.data) }
        return b
    }

    func snapshot(_ folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name != ".lock" {
            var isDir: ObjCBool = false
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            result[name] = try Data(contentsOf: url)
        }
        return result
    }

    // MARK: - Case-alias ids (#4)

    func testFileKeyIgnoresCaseAndUnicodeForm() {
        XCTAssertEqual(HistoryStore.fileKey("Example"), HistoryStore.fileKey("example"))
        XCTAssertEqual(HistoryStore.fileKey("Caf\u{E9}"), HistoryStore.fileKey("cafe\u{301}"))
        XCTAssertNotEqual(HistoryStore.fileKey("Example"), HistoryStore.fileKey("Examples"))
    }

    /// Two ids that differ only in case: the file is refused before any write, on any volume.
    func testBackupWithCaseAliasIDsIsRefused() throws {
        let target = try HistoryStore(folder: history("target"))
        try target.add(xml("Mine"), cls: .XMSS)
        let before = try snapshot(target.folder)

        let file = root.appendingPathComponent("case-pair.json")
        try backup([xml("One"), xml("Two")], ids: ["Example", "example"]).write(to: file)
        XCTAssertThrowsError(try Backup.read(from: file)) { error in
            XCTAssertEqual(error as? Backup.BackupError, .caseDuplicateID("Example", "example"))
        }
        XCTAssertEqual(try snapshot(target.folder), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.backupsFolder.path))
    }

    /// Replace from `Original` to `original` keeps the new XML and the entry (cleanup compares without case).
    func testReplaceWithCaseChangedIDKeepsNewXML() throws {
        let target = try HistoryStore(folder: history("target"))
        try target.replace(with: try backup([xml("Old")], ids: ["Original"]))
        XCTAssertEqual(target.entries.map(\.id), ["Original"])

        try target.replace(with: try backup([xml("New")], ids: ["original"]))
        XCTAssertEqual(target.entries.map(\.id), ["original"])
        let entry = try XCTUnwrap(target.entry(id: "original"))
        XCTAssertEqual(try target.data(for: entry), xml("New"))
        XCTAssertEqual(entry.folder, "Keep")

        // A store that opens the history again: no repair, the same entry and bytes, no old file brought back.
        let reopened = try HistoryStore(folder: history("target"))
        XCTAssertEqual(reopened.repairLog, [])
        XCTAssertEqual(reopened.entries.map(\.id), ["original"])
        XCTAssertEqual(try reopened.data(for: XCTUnwrap(reopened.entry(id: "original"))), xml("New"))
    }

    /// Merge: an id that matches an existing id without case gets a new id; both entries keep their bytes.
    func testMergeWithCaseAliasIDGetsNewID() throws {
        let target = try HistoryStore(folder: history("target"))
        try target.replace(with: try backup([xml("Old")], ids: ["Original"]))

        let result = try target.merge(try backup([xml("Other")], ids: ["original"]))
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(target.entries.count, 2)
        let new = try XCTUnwrap(target.entries.first { $0.id != "Original" })
        XCTAssertNotEqual(HistoryStore.fileKey(new.id), HistoryStore.fileKey("Original"))
        XCTAssertEqual(try target.data(for: new), xml("Other"))
        XCTAssertEqual(try target.data(for: XCTUnwrap(target.entry(id: "Original"))), xml("Old"))
        XCTAssertEqual(try HistoryStore(folder: history("target")).entries.count, 2)
    }

    // MARK: - Settings changes and the limit (#3)

    func testOnlyALimitChangeTrims() throws {
        let source = try HistoryStore(folder: history("source"))
        for i in 1...15 { try source.add(xml("Loose \(i)"), cls: .XMSS) }
        try source.add(xml("Kept"), cls: .XMSS, folder: "Keep")
        let target = try HistoryStore(folder: history("target"))
        try target.updateSettings { $0.uncategorizedLimit = 10 }
        try target.merge(source.makeBackup())  // a Merge does not trim: 15 uncategorized, limit 10
        XCTAssertEqual(target.uncategorizedCount, 15)

        XCTAssertEqual(try target.updateSettings { $0.appearance = "dark" }.count, 0)
        XCTAssertEqual(try target.updateSettings { $0.uncategorizedName = "Inbox" }.count, 0)
        XCTAssertEqual(try target.updateSettings { $0.uncategorizedLimit = 10 }.count, 0)  // the same limit
        XCTAssertEqual(target.uncategorizedCount, 15)
        XCTAssertEqual(target.settings.appearance, "dark")
        XCTAssertEqual(target.settings.uncategorizedName, "Inbox")

        let gone = try target.updateSettings { $0.uncategorizedLimit = 12 }
        XCTAssertEqual(gone.count, 3)
        XCTAssertEqual(target.uncategorizedCount, 12)
        XCTAssertEqual(target.entries.filter { $0.folder == "Keep" }.count, 1)
    }

    // MARK: - A Replace by another process, seen by the app (#4)

    func testReplaceWritesNewGenerationAndMergeKeepsIt() throws {
        let store = try HistoryStore(folder: history("h"))
        XCTAssertNil(store.generation)
        try store.replace(with: try backup([xml("A")], ids: ["a"]))
        let first = try XCTUnwrap(store.generation)
        try store.merge(try backup([xml("B")], ids: ["b"]))
        XCTAssertEqual(store.generation, first)
        try store.replace(with: try backup([xml("C")], ids: ["c"]))
        XCTAssertNotEqual(store.generation, first)
    }

    /// The review's model reproduction: Delete with Undo, then a Replace by a second store (as the CLI does), then the
    /// watcher's `reloadFromDisk()`. The old Undo is gone, nothing comes back, and the text cache shows the new XML.
    func testExternalReplaceClearsUndoAndCaches() throws {
        let store = try HistoryStore(folder: history("h"))
        let before = xml("Before")
        let after = xml("After")
        let entry = try store.add(before, cls: .XMSS)
        let deleted = try store.add(Data("<Deleted/>".utf8), cls: .XMSS)
        let model = AppModel(store: store, watch: false)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        undo.beginUndoGrouping()
        model.delete(deleted.id)
        undo.endUndoGrouping()
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(model.text(for: entry), String(decoding: before, as: UTF8.self))

        let external = try HistoryStore(folder: history("h"))
        var b = try external.makeBackup()
        let changed = HistoryEntry(id: entry.id, cls: entry.cls, time: entry.time, title: "After", titleVersion: 999,
                                   sha256: HistoryStore.sha256(after), source: entry.source,
                                   canonical: Canonical.key(for: after))
        b.items = [Backup.Item(entry: changed, data: after)]
        try external.replace(with: b)

        model.reloadFromDisk()
        XCTAssertFalse(undo.canUndo)
        undo.undo()  // nothing to undo
        XCTAssertFalse(model.entries.contains { $0.id == deleted.id })
        XCTAssertEqual(model.text(for: model.entries[0]), String(decoding: after, as: UTF8.self))
    }

    /// Any reload drops the cache of an entry whose bytes changed, also without a Replace.
    func testReloadDropsCacheOfChangedEntry() throws {
        let store = try HistoryStore(folder: history("h"))
        let entry = try store.add(xml("Before"), cls: .XMSS, folder: "Keep")
        let model = AppModel(store: store, watch: false)
        XCTAssertEqual(model.text(for: entry), String(decoding: xml("Before"), as: UTF8.self))

        // Another process puts other bytes under the same id and index entry (a Merge cannot do this; write directly).
        let external = try HistoryStore(folder: history("h"))
        let after = xml("After")
        try external.withLock {
            let old = external.entries[0]
            var e = HistoryEntry(id: old.id, cls: old.cls, time: old.time, title: "After", titleVersion: 999,
                                 sha256: HistoryStore.sha256(after), source: old.source,
                                 canonical: Canonical.key(for: after))
            e.folder = old.folder
            try after.write(to: external.fileURL(for: e), options: .atomic)
            external.entries[0] = e
            try external.saveIndex()
        }
        model.reloadFromDisk()
        XCTAssertEqual(model.text(for: model.entries[0]), String(decoding: after, as: UTF8.self))
        XCTAssertEqual(store.generation, nil)  // not a Replace
    }
}
