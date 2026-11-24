import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The context menu of an entry row obeys the Finder rule (the bug: "Cmd+A, then right-click > Delete deletes one").
final class ContextMenuTests: XCTestCase {
    var folder: URL!
    var store: HistoryStore!
    var undo: UndoManager!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        store = try HistoryStore(folder: folder)
        for i in 1...4 {
            try store.add(Data("<fmxmlsnippet><Step name=\"RC \(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS,
                          name: "Project RC \(i)", folder: "Project RC")
        }
        try store.add(Data("<fmxmlsnippet><Step name=\"Other\"/></fmxmlsnippet>".utf8), cls: .XMSS, name: "Other")
        _ = try store.makeFolder("Target")
        undo = UndoManager()
        undo.groupsByEvent = false
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func makeModel() -> AppModel {
        let model = AppModel(store: store, watch: false)
        model.undoManager = undo
        model.expandedFolders = ["Project RC"]
        model.noFolderExpanded = false  // only the 4 test entries are visible
        return model
    }

    func testRightClickInTheSelectionActsOnAllAndKeepsTheSelection() throws {
        let model = makeModel()
        model.selectAll()
        let all = Set(model.visibleIDs)
        XCTAssertEqual(all.count, 4)
        let row = model.visibleIDs[2]

        model.contextClick(row)
        XCTAssertEqual(model.listSelection.ids, all)  // the right-click did not change the selection
        XCTAssertEqual(model.contextDeleteTitle(for: row), "Delete 4 Entries…")
        XCTAssertTrue(model.contextActsOnMany(row))  // Copy, Rename and Save As are disabled

        var asked: [Int] = []
        model.confirmBulkDelete = { count, answer in asked.append(count); answer(true) }
        undo.beginUndoGrouping()
        model.contextDelete(row)
        undo.endUndoGrouping()
        XCTAssertEqual(asked, [4])
        XCTAssertEqual(try HistoryStore(folder: folder).entries.map(\.name), ["Other"])

        undo.undo()  // one Cmd+Z puts all 4 back
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 5)
    }

    func testRightClickOutsideTheSelectionSelectsOnlyThatRow() {
        let model = makeModel()
        let ids = model.visibleIDs
        model.click(ids[0], modifiers: [])
        model.click(ids[1], modifiers: .command)
        XCTAssertEqual(model.listSelection.count, 2)

        model.contextClick(ids[3])
        XCTAssertEqual(model.listSelection.ids, [ids[3]])
        XCTAssertEqual(model.contextDeleteTitle(for: ids[3]), "Delete")
        XCTAssertFalse(model.contextActsOnMany(ids[3]))

        var asked = 0
        model.confirmBulkDelete = { _, answer in asked += 1; answer(true) }
        undo.beginUndoGrouping()
        model.contextDelete(ids[3])
        undo.endUndoGrouping()
        XCTAssertEqual(asked, 0)  // one entry: no question
        XCTAssertEqual(store.entries.count, 4)
        XCTAssertNil(store.entry(id: ids[3]))
    }

    func testTitlesBeforeTheRightClickMatchTheAction() {
        // SwiftUI can build the menu before the right-click: a row outside a multi-selection still shows "Delete".
        let model = makeModel()
        let ids = model.visibleIDs
        model.selectAll()
        model.click(ids[0], modifiers: .command)  // ids[0] is not in the selection now
        XCTAssertEqual(model.contextDeleteTitle(for: ids[0]), "Delete")
        XCTAssertEqual(model.contextDeleteTitle(for: ids[1]), "Delete 3 Entries…")
    }

    func testMoveToFolderInTheSelectionMovesAll() throws {
        let model = makeModel()
        model.selectAll()
        model.contextMove(model.visibleIDs[1], to: "Target")
        let moved = try HistoryStore(folder: folder).entries.filter { $0.folder == "Target" }
        XCTAssertEqual(moved.count, 4)
        XCTAssertEqual(model.listSelection.count, 4)
    }

    func testCopyRenameSaveDoNothingForMany() {
        let model = makeModel()
        model.selectAll()
        model.contextRename(model.visibleIDs[0])
        XCTAssertNil(model.prompt)
        XCTAssertEqual(model.listSelection.count, 4)
    }
}
