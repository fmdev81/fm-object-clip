import AppKit
import XCTest
@testable import FMClipCore

final class FolderTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func xml(_ i: Int) -> Data {
        Data("<fmxmlsnippet><Step name=\"Step \(i)\"/></fmxmlsnippet>".utf8)
    }

    func testMakeRenameDeleteFolder() throws {
        let store = try HistoryStore(folder: folder)
        XCTAssertEqual(try store.makeFolder("  Project A "), "Project A")
        XCTAssertEqual(try store.makeFolder("project a"), "Project A")  // the same folder, any case
        try store.makeFolder("Tokyo")
        XCTAssertEqual(store.folders, ["Project A", "Tokyo"])
        XCTAssertThrowsError(try store.makeFolder("  ")) { XCTAssertEqual($0 as? HistoryStore.FolderError, .emptyName) }

        let e = try store.add(xml(1), cls: .XMSS, folder: "Project A")
        try store.renameFolder("Project A", to: "Project A Archive")
        XCTAssertEqual(store.folders, ["Project A Archive", "Tokyo"])
        XCTAssertEqual(store.entry(id: e.id)?.folder, "Project A Archive")  // the entries go with the folder
        XCTAssertThrowsError(try store.renameFolder("Tokyo", to: "project a archive")) {
            XCTAssertEqual($0 as? HistoryStore.FolderError, .exists("Project A Archive"))
        }

        try store.deleteFolder("Project A Archive")
        XCTAssertEqual(store.folders, ["Tokyo"])
        XCTAssertNotNil(store.entry(id: e.id))  // the entry stays in the history
        XCTAssertNil(store.entry(id: e.id)?.folder)

        // The folders and the folder of each entry stay after the store opens again.
        try store.move(id: e.id, to: "Tokyo")
        let again = try HistoryStore(folder: folder)
        XCTAssertEqual(again.folders, ["Tokyo"])
        XCTAssertEqual(again.entry(id: e.id)?.folder, "Tokyo")
    }

    func testMoveToFolderAndBack() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMFD)
        let e = try store.add(data, cls: .XMFD)
        XCTAssertNil(e.folder)
        XCTAssertEqual(try store.move(id: e.id, to: "New folder")?.folder, "New folder")
        XCTAssertEqual(store.folders, ["New folder"])  // the store makes the folder
        XCTAssertEqual(store.count(in: "New folder"), 1)
        XCTAssertNil(try store.move(id: e.id, to: nil)?.folder)
        XCTAssertNil(try store.move(id: e.id, to: "  ")?.folder)
        XCTAssertEqual(store.folders, ["New folder"])  // the empty folder stays
        XCTAssertEqual(try store.data(for: store.entry(id: e.id)!), data)  // the XML does not change
        XCTAssertNil(try store.move(id: "no-such-id", to: "x"))
    }

    func testAddWithFolder() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let data = Samples.data(for: .XML2)
        let store = try HistoryStore(folder: folder)
        let e = try store.add(data, cls: .XML2, name: "Contact card", folder: " Project A ")
        XCTAssertEqual(e.folder, "Project A")
        XCTAssertEqual(store.folders, ["Project A"])  // the store makes the folder
        let index = (try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("index.json"))) as! [[String: Any]]).map { $0.mapValues { "\($0)" } }
        XCTAssertEqual(index[0]["folder"], "Project A")

        // Copy puts out the same bytes, with the FileMaker class only.
        try store.copy(e, to: pasteboard)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XML2, data: data)])
        XCTAssertEqual(pasteboard.data(forType: FMClass.XML2.pasteboardType), data)
    }

    func testSameXMLWithNewFolderMovesTheEntry() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMTB)
        let e = try store.add(data, cls: .XMTB, folder: "Project A")
        try store.add(xml(1), cls: .XMSS)
        let again = try store.add(data, cls: .XMTB, folder: "Project B")
        XCTAssertEqual(again.id, e.id)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].folder, "Project B")
        XCTAssertEqual(store.folders, ["Project A", "Project B"])
        try store.add(data, cls: .XMTB)  // no folder: the entry stays in its folder
        XCTAssertEqual(store.entries[0].folder, "Project B")
    }

    func testSizeLimitKeepsEntriesInFolders() throws {
        let store = try HistoryStore(folder: folder, limit: 5)
        let kept = try store.add(xml(0), cls: .XMSS, folder: "Keep")
        for i in 1...10 { try store.add(xml(i), cls: .XMSS) }
        XCTAssertEqual(store.entries.count, 5)
        XCTAssertNotNil(store.entry(id: kept.id))  // the oldest entry stays, because it is in a folder
        XCTAssertEqual(store.entries.filter { $0.folder == nil }.count, 4)

        // When all the entries over the limit are in folders, the store deletes nothing.
        for i in 11...16 { try store.add(xml(i), cls: .XMSS, folder: "Keep") }
        XCTAssertEqual(store.entries.filter { $0.folder == "Keep" }.count, 7)
        XCTAssertEqual(store.entries.filter { $0.folder == nil }.count, 0)

        // A deleted folder gives its entries back to the limit.
        try store.deleteFolder("Keep")
        XCTAssertEqual(store.entries.count, 5)
    }

    func testRepairAddsMissingFolders() throws {
        let store = try HistoryStore(folder: folder)
        let e = try store.add(xml(1), cls: .XMSS, folder: "Lost")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("folders.json"))
        let again = try HistoryStore(folder: folder)
        XCTAssertEqual(again.folders, ["Lost"])
        XCTAssertEqual(again.entry(id: e.id)?.folder, "Lost")
    }
}
