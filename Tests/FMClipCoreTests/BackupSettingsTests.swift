import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// Backup (#4) together with the settings (#3): a Replace restores the settings, a Merge keeps the current settings.
final class BackupSettingsTests: XCTestCase {
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

    static let custom = ClipSettings(appearance: "dark", uncategorizedName: "Inbox", uncategorizedLimit: 50)

    /// A history with two entries and non-default settings, written through the settings API of #3.
    func makeSource() throws -> HistoryStore {
        let store = try HistoryStore(folder: history("source"))
        try store.add(xml(1), cls: .XMSS, folder: "Work")
        try store.add(xml(2), cls: .XMSS)
        try store.updateSettings { $0 = Self.custom }
        XCTAssertEqual(store.settings, Self.custom)
        return store
    }

    func testReplaceRestoresSettings() throws {
        let backup = try makeSource().makeBackup()
        let target = try HistoryStore(folder: history("target"))  // empty, default settings, no fixed limit
        XCTAssertEqual(target.settings, ClipSettings())
        XCTAssertEqual(target.limit, ClipSettings.defaultUncategorizedLimit)

        try target.replace(with: backup)
        XCTAssertEqual(target.settings, Self.custom)
        XCTAssertEqual(target.limit, 50)
        XCTAssertEqual(target.entries.count, 2)
        // A store that opens the history again sees the same settings.
        let reopened = try HistoryStore(folder: history("target"))
        XCTAssertEqual(reopened.settings, Self.custom)
        XCTAssertEqual(reopened.limit, 50)
    }

    func testMergeKeepsCurrentSettings() throws {
        let backup = try makeSource().makeBackup()
        let target = try HistoryStore(folder: history("target"))
        let current = ClipSettings(appearance: "light", uncategorizedName: "Loose", uncategorizedLimit: 300)
        try target.updateSettings { $0 = current }

        let result = try target.merge(backup)
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(target.settings, current)
        XCTAssertEqual(target.limit, 300)
        XCTAssertEqual(try HistoryStore(folder: history("target")).settings, current)
    }

    /// The app path: File > Restore from Backup… > Replace calls `reloadAfterRestore()`. The window must show the
    /// restored settings at once (name, limit, appearance) without a restart.
    func testAppShowsRestoredSettingsAfterReplace() throws {
        let backup = try makeSource().makeBackup()
        let target = try HistoryStore(folder: history("target"))
        let model = AppModel(store: target, watch: false)
        XCTAssertEqual(model.uncategorizedName, ClipSettings.defaultUncategorizedName)

        try XCTUnwrap(model.store).replace(with: backup)
        model.reloadAfterRestore()
        XCTAssertEqual(model.settings, Self.custom)
        XCTAssertEqual(model.uncategorizedName, "Inbox")
        XCTAssertEqual(model.settings.uncategorizedLimit, 50)
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.folders, ["Work"])
        XCTAssertEqual(AppModel.nsAppearance(for: model.settings.appearance)?.name, .darkAqua)
    }
}
