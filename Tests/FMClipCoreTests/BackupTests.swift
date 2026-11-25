import AppKit
import XCTest
@testable import FMClipCore

final class BackupTests: XCTestCase {
    var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func history(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    func xml(_ i: Int) -> Data {
        Data("<fmxmlsnippet><Step name=\"Step \(i)\"/></fmxmlsnippet>".utf8)
    }

    func writeSettings(_ object: [String: Any], to folder: URL) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: folder.appendingPathComponent("settings.json"))
    }

    func readSettings(_ folder: URL) -> NSDictionary? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
    }

    /// A history with three entries, two folders (one empty) and a settings file.
    func makeSource(_ name: String = "source") throws -> HistoryStore {
        let store = try HistoryStore(folder: history(name))
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try store.add(Samples.data(for: .XMSS), cls: .XMSS, name: "Steps", folder: "Invoicing", now: t)
        try store.add(xml(1), cls: .XMSS, now: t.addingTimeInterval(10))
        try store.add(Samples.data(for: .XMFD), cls: .XMFD, folder: "CRM", now: t.addingTimeInterval(20))
        try store.makeFolder("Empty")
        try writeSettings(["limit": 50, "nested": ["a": [1, 2, 3]], "flag": true], to: store.folder)
        return store
    }

    /// The state of a history folder, to see that nothing changed.
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

    func testFileFormat() throws {
        let store = try makeSource()
        let url = root.appendingPathComponent("b.json")
        try store.writeBackup(to: url, now: Date(timeIntervalSince1970: 0))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "fm-object-clip-backup")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["created"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(json["folders"] as? [String], ["Invoicing", "CRM", "Empty"])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["id"] as? String }, store.entries.map(\.id))  // index order, newest first
        XCTAssertEqual(entries.first?["class"] as? String, "XMFD")
        XCTAssertEqual(Data(base64Encoded: entries.first?["data"] as? String ?? ""), Samples.data(for: .XMFD))
        XCTAssertTrue(Backup.defaultFileName().hasPrefix("fm-object-clip-backup-"))
        XCTAssertTrue(Backup.defaultFileName().hasSuffix(".json"))
    }

    func testRoundTripReplaceIntoEmptyHistory() throws {
        let source = try makeSource()
        let url = root.appendingPathComponent("b.json")
        try source.writeBackup(to: url)

        let target = try HistoryStore(folder: history("target"))
        let result = try target.replace(with: try Backup.read(from: url))
        XCTAssertEqual(result.entries, 3)
        XCTAssertEqual(target.entries, source.entries)  // ids, names, folders, times, sha256
        XCTAssertEqual(target.folders, source.folders)
        for e in target.entries {
            XCTAssertEqual(try target.data(for: e), try source.data(for: e))
            XCTAssertEqual(HistoryStore.sha256(try target.data(for: e)), e.sha256)
        }
        XCTAssertEqual(readSettings(target.folder), readSettings(source.folder))

        // The files on disk agree after the store opens again.
        let again = try HistoryStore(folder: history("target"))
        XCTAssertEqual(again.entries, source.entries)
        XCTAssertEqual(again.folders, source.folders)
    }

    func testReplaceRemovesOldEntriesAndSettings() throws {
        let source = try HistoryStore(folder: history("source"))
        try source.add(xml(1), cls: .XMSS)
        let backup = try source.makeBackup()  // no settings.json: settings is null

        let target = try makeSource("target")
        let old = target.entries
        target.forgetRestore()
        _ = try target.copy(old[0], to: NSPasteboard(name: NSPasteboard.Name("fm-object-clip-test-\(UUID().uuidString)")))
        XCTAssertNotNil(target.lastRestore())
        try target.replace(with: backup)
        XCTAssertEqual(target.entries, source.entries)
        XCTAssertEqual(target.folders, [])
        XCTAssertNil(readSettings(target.folder))
        XCTAssertNil(target.lastRestore())  // the restore record is cleared
        for e in old { XCTAssertFalse(FileManager.default.fileExists(atPath: target.fileURL(for: e).path)) }
    }

    func testReplaceWritesSafetyBackupFirst() throws {
        let target = try makeSource()
        let before = try target.makeBackup()
        let empty = try HistoryStore(folder: history("empty")).makeBackup()

        let result = try target.replace(with: empty, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(result.safetyBackup.deletingLastPathComponent().standardizedFileURL,
                       root.appendingPathComponent("backups").standardizedFileURL)
        XCTAssertTrue(result.safetyBackup.lastPathComponent.hasPrefix("fm-object-clip-before-restore-"))
        XCTAssertTrue(target.entries.isEmpty)

        // The safety backup holds the history from before the Replace; it restores it.
        let safety = try Backup.read(from: result.safetyBackup)
        XCTAssertEqual(safety.items.map(\.entry), before.items.map(\.entry))
        XCTAssertEqual(safety.folders, before.folders)
        XCTAssertEqual(safety.settings.map { $0 as NSDictionary }, before.settings.map { $0 as NSDictionary })

        // A second Replace in the same second does not overwrite the first safety backup.
        let second = try target.replace(with: safety, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNotEqual(second.safetyBackup, result.safetyBackup)
        XCTAssertEqual(target.entries, before.items.map(\.entry))
    }

    func testFailedReplaceChangesNothing() throws {
        let source = try makeSource()
        let backup = try source.makeBackup()
        let target = try HistoryStore(folder: history("target"))
        try target.add(xml(7), cls: .XMSS, folder: "T")
        try writeSettings(["x": 1], to: target.folder)
        // A folder with the file name of the last entry: the write of that XML file fails in the middle.
        let blocker = target.folder.appendingPathComponent("\(backup.items.last!.entry.id).xml")
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: blocker.appendingPathComponent("x"), withIntermediateDirectories: false)
        let before = try snapshot(target.folder)
        let entries = target.entries

        XCTAssertThrowsError(try target.replace(with: backup))
        XCTAssertEqual(try snapshot(target.folder), before)
        XCTAssertEqual(target.entries, entries)
        XCTAssertEqual(try HistoryStore(folder: target.folder).entries, entries)
    }

    func testMergeSkipsDuplicates() throws {
        let source = try makeSource()
        let backup = try source.makeBackup()

        let target = try HistoryStore(folder: history("target"))
        let t = Date(timeIntervalSince1970: 1_900_000_000)
        // The same steps as in the backup, pretty-printed: the same canonical XML, so a duplicate.
        let pretty = Data(XMLFormat.pretty(String(decoding: Samples.data(for: .XMSS), as: UTF8.self)).utf8)
        XCTAssertNotEqual(pretty, Samples.data(for: .XMSS))
        try target.add(pretty, cls: .XMSS, now: t)
        try target.add(xml(1), cls: .XMSS, folder: "crm", now: t)  // the same bytes; "crm" is "CRM" in another case
        try target.add(xml(99), cls: .XMSS, now: t)
        try writeSettings(["mine": 1], to: target.folder)

        let result = try target.merge(backup)
        XCTAssertEqual(result, HistoryStore.MergeResult(added: 1, skippedDuplicates: 2, foldersAdded: 2))
        XCTAssertEqual(target.entries.count, 4)
        XCTAssertEqual(target.folders, ["crm", "Invoicing", "Empty"])  // after the current folders, in backup order
        let added = try XCTUnwrap(target.entries.first { $0.cls == .XMFD })
        let original = try XCTUnwrap(source.entries.first { $0.cls == .XMFD })
        XCTAssertEqual(added.id, original.id)
        XCTAssertEqual(added.time, original.time)
        XCTAssertEqual(added.folder, "crm")  // the existing folder, any case
        XCTAssertEqual(try target.data(for: added), Samples.data(for: .XMFD))
        XCTAssertEqual(readSettings(target.folder), ["mine": 1] as NSDictionary)  // the settings do not change

        // A second merge adds nothing.
        XCTAssertEqual(try target.merge(backup), HistoryStore.MergeResult(added: 0, skippedDuplicates: 3, foldersAdded: 0))
        XCTAssertEqual(target.entries.count, 4)
    }

    func testMergeGivesNewIDWhenIDIsInUse() throws {
        let source = try HistoryStore(folder: history("source"))
        let e = try source.add(xml(1), cls: .XMSS, folder: "A")
        var backup = try source.makeBackup()
        // The same id, other content.
        let other = xml(2)
        let entry = HistoryEntry(id: e.id, cls: .XMSS, time: e.time, title: "x", titleVersion: Titles.version,
                                 sha256: HistoryStore.sha256(other), source: "clipboard", name: "Other", folder: nil,
                                 canonical: nil)
        backup.items.append(Backup.Item(entry: entry, data: other))

        let target = try HistoryStore(folder: history("target"))
        try target.insert(e, data: xml(1))
        let result = try target.merge(backup)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skippedDuplicates, 1)
        let added = try XCTUnwrap(target.entries.first { $0.name == "Other" })
        XCTAssertNotEqual(added.id, e.id)
        XCTAssertEqual(try target.data(for: added), other)
        XCTAssertEqual(try target.data(for: target.entry(id: e.id)!), xml(1))  // the old entry does not change
    }

    func testMergeKeepsFolderEntriesOverLimit() throws {
        let source = try HistoryStore(folder: history("source"))
        for i in 0..<5 { try source.add(xml(i), cls: .XMSS, folder: "Keep") }
        let target = try HistoryStore(folder: history("target"), limit: 3)
        try target.merge(try source.makeBackup())
        XCTAssertEqual(target.count(in: "Keep"), 5)
    }

    // MARK: - Refusal

    func backupJSON(_ store: HistoryStore) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try store.makeBackup().encoded()) as? [String: Any])
    }

    func assertRefused(_ json: Any, file: StaticString = #filePath, line: UInt = #line,
                       _ check: (Backup.BackupError) -> Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        let target = try makeTargetOnce()
        let before = try snapshot(target.folder)
        XCTAssertThrowsError(try Backup.decode(data), file: file, line: line) { error in
            XCTAssertTrue(check(error as! Backup.BackupError), "\(error)", file: file, line: line)
        }
        // A bad file changes nothing: the decode throws before the store sees it.
        XCTAssertThrowsError(try target.merge(try Backup.decode(data)), file: file, line: line)
        XCTAssertThrowsError(try target.replace(with: try Backup.decode(data)), file: file, line: line)
        XCTAssertEqual(try snapshot(target.folder), before, file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.backupsFolder.path), file: file, line: line)
    }

    private var target: HistoryStore?
    func makeTargetOnce() throws -> HistoryStore {
        if let target { return target }
        let store = try HistoryStore(folder: history("target"))
        try store.add(xml(7), cls: .XMSS, folder: "T")
        try writeSettings(["x": 1], to: store.folder)
        target = store
        return store
    }

    func testRefusesBadFiles() throws {
        let good = try backupJSON(try makeSource())

        try assertRefused(["hello": "world"]) { if case .notBackup = $0 { return true }; return false }
        try assertRefused([1, 2, 3]) { if case .notBackup = $0 { return true }; return false }

        var wrongFormat = good
        wrongFormat["format"] = "something-else"
        try assertRefused(wrongFormat) { if case .notBackup = $0 { return true }; return false }

        var newer = good
        newer["version"] = 2
        try assertRefused(newer) { $0 == .newerVersion(2) }

        var older = good
        older["version"] = 0
        try assertRefused(older) { $0 == .unknownVersion(0) }

        var noVersion = good
        noVersion["version"] = "1"
        try assertRefused(noVersion) { if case .notBackup = $0 { return true }; return false }

        var entries = try XCTUnwrap(good["entries"] as? [[String: Any]])
        var badBase64 = good
        entries[1]["data"] = "not base64 !!!"
        badBase64["entries"] = entries
        try assertRefused(badBase64) { if case .badData = $0 { return true }; return false }

        entries = try XCTUnwrap(good["entries"] as? [[String: Any]])
        var mismatch = good
        entries[2]["data"] = Data("<other/>".utf8).base64EncodedString()
        mismatch["entries"] = entries
        try assertRefused(mismatch) { if case .checksum = $0 { return true }; return false }

        entries = try XCTUnwrap(good["entries"] as? [[String: Any]])
        var missingField = good
        entries[0]["sha256"] = nil
        missingField["entries"] = entries
        try assertRefused(missingField) { if case .badEntry(0, _) = $0 { return true }; return false }

        entries = try XCTUnwrap(good["entries"] as? [[String: Any]])
        var unsafeID = good
        entries[0]["id"] = "../../escape"
        unsafeID["entries"] = entries
        try assertRefused(unsafeID) { if case .badEntry(0, _) = $0 { return true }; return false }

        entries = try XCTUnwrap(good["entries"] as? [[String: Any]])
        var twice = good
        entries[1]["id"] = entries[0]["id"]
        twice["entries"] = entries
        try assertRefused(twice) { if case .duplicateID = $0 { return true }; return false }

        var badSettings = good
        badSettings["settings"] = [1, 2]
        try assertRefused(badSettings) { if case .notBackup = $0 { return true }; return false }

        // Not JSON at all.
        XCTAssertThrowsError(try Backup.decode(Data("not json".utf8)))
    }
}
