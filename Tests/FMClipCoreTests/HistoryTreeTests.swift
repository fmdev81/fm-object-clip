import XCTest
@testable import FMClipCore

final class HistoryTreeTests: XCTestCase {
    func entry(_ id: String, _ cls: FMClass, folder: String? = nil, name: String? = nil) -> HistoryEntry {
        HistoryEntry(id: id, cls: cls, time: "T", title: id, sha256: id, source: "clipboard", name: name, folder: folder)
    }

    lazy var entries = [
        entry("a", .XMSS, folder: "Project A"),
        entry("b", .XMFD, folder: "Project A"),
        entry("c", .XMTB, folder: "Project B"),
        entry("d", .XML2),
        entry("e", .XMFD),
    ]
    let folders = ["Project A", "Project B", "Unused"]

    func ids(_ rows: [TreeRow]) -> [String] { rows.map(\.id) }

    func testCollapsedFoldersShowOnlyTheFolderRows() {
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: [], active: false) { _ in true }
        XCTAssertEqual(ids(rows), ["folder:Project A", "folder:Project B", "folder:Unused", "no-folder", "d", "e"])
        XCTAssertEqual(rows[0].kind, .folder(name: "Project A", count: 2, expanded: false))
        XCTAssertEqual(rows[2].kind, .folder(name: "Unused", count: 0, expanded: false))  // empty folders show
        XCTAssertEqual(rows[3].kind, .noFolder(count: 2, expanded: true))  // "No Folder" is open by default
        XCTAssertEqual(rows[4].kind, .entry(entries[3], indented: true))  // each entry is under a group row
    }

    func testExpandedFolderShowsItsEntriesIndented() {
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: ["Project A"], active: false) { _ in true }
        XCTAssertEqual(ids(rows), ["folder:Project A", "a", "b", "folder:Project B", "folder:Unused", "no-folder", "d", "e"])
        XCTAssertEqual(rows[0].kind, .folder(name: "Project A", count: 2, expanded: true))
        XCTAssertEqual(rows[1].kind, .entry(entries[0], indented: true))
    }

    func testFilterShowsOnlyFoldersWithAMatchExpanded() {
        let fields = { (e: HistoryEntry) in e.cls == .XMFD }
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: [], active: true, matches: fields)
        XCTAssertEqual(ids(rows), ["folder:Project A", "b", "no-folder", "e"])  // Project B and Unused have no match
        XCTAssertEqual(rows[0].kind, .folder(name: "Project A", count: 1, expanded: true))  // expanded, count of matches
    }

    func testSearchWithNoMatch() {
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: ["Project A"], active: true) { _ in false }
        XCTAssertEqual(rows, [])
    }

    func testEntryWithAnUnknownFolderShowsAtTheTopLevel() {
        let stray = [entry("x", .XMSS, folder: "Gone")]
        let rows = HistoryTree.rows(entries: stray, folders: [], expanded: [], active: false) { _ in true }
        XCTAssertEqual(ids(rows), ["no-folder", "x"])
    }

    func testNoFolderGroupCollapsed() {
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: [], noFolderExpanded: false, active: false) { _ in true }
        XCTAssertEqual(ids(rows), ["folder:Project A", "folder:Project B", "folder:Unused", "no-folder"])
        XCTAssertEqual(rows[3].kind, .noFolder(count: 2, expanded: false))
    }

    func testNoFolderGroupOpensWhileFiltering() {
        let layout = { (e: HistoryEntry) in e.cls == .XML2 }
        let rows = HistoryTree.rows(entries: entries, folders: folders, expanded: [], noFolderExpanded: false, active: true, matches: layout)
        XCTAssertEqual(ids(rows), ["no-folder", "d"])
        XCTAssertEqual(rows[0].kind, .noFolder(count: 1, expanded: true))
    }

    func testNoFolderGroupHiddenWithoutLooseEntries() {
        let inFolders = Array(entries.prefix(3))
        let rows = HistoryTree.rows(entries: inFolders, folders: folders, expanded: [], active: false) { _ in true }
        XCTAssertFalse(ids(rows).contains("no-folder"))
    }
}
