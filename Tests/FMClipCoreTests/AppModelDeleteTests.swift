import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The select-all-then-delete path of the window model (the bug: "delete does not work after Cmd+A").
final class AppModelDeleteTests: XCTestCase {
    var folder: URL!
    var store: HistoryStore!
    var undo: UndoManager!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        store = try HistoryStore(folder: folder)
        for i in 1...6 {
            try store.add(Data("<fmxmlsnippet><Step name=\"Test \(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS,
                          name: "Project All \(i)", folder: "Project All")
        }
        try store.add(Data("<fmxmlsnippet><Step name=\"Other A\"/></fmxmlsnippet>".utf8), cls: .XMSS, name: "Other A")
        try store.add(Data("<fmxmlsnippet><Step name=\"Other B\"/></fmxmlsnippet>".utf8), cls: .XMSS, name: "Other B")
        undo = UndoManager()
        undo.groupsByEvent = false
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func makeModel() -> AppModel {
        let model = AppModel(store: store, watch: false)
        model.undoManager = undo
        model.expandedFolders = []
        model.noFolderExpanded = true
        return model
    }

    func deleteSelected(_ model: AppModel) {
        undo.beginUndoGrouping()
        model.deleteSelected()
        undo.endUndoGrouping()
    }

    func testSelectAllThenDeleteDeletesTheVisibleEntriesAfterOneQuestion() throws {
        let model = makeModel()
        model.search = "Project All"  // only the 6 test entries are visible
        model.selectAll()
        XCTAssertEqual(model.listSelection.count, 6)
        XCTAssertTrue(model.canDeleteSelection)
        XCTAssertEqual(model.deleteMenuTitle, "Delete 6 Entries…")

        var asked: [Int] = []
        model.confirmBulkDelete = { count, answer in
            asked.append(count)
            answer(true)
        }
        deleteSelected(model)
        XCTAssertEqual(asked, [6])  // one question for all the entries
        XCTAssertEqual(try HistoryStore(folder: folder).entries.map(\.name), ["Other B", "Other A"])
        XCTAssertTrue(model.listSelection.isEmpty)

        // One Undo puts the 6 entries back, selected.
        undo.undo()
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 8)
        XCTAssertEqual(model.listSelection.count, 6)
        XCTAssertEqual(model.deleteMenuTitle, "Delete 6 Entries…")
    }

    func testCancelDeletesNothing() throws {
        let model = makeModel()
        model.search = "Project All"
        model.selectAll()
        model.confirmBulkDelete = { _, answer in answer(false) }
        deleteSelected(model)
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 8)
        XCTAssertEqual(model.listSelection.count, 6)
    }

    func testSelectAllUsesTheOpenFoldersAndShiftClickSelectsAll() throws {
        let model = makeModel()
        // Project All is closed: Cmd+A selects only the 2 visible entries in No Folder.
        model.selectAll()
        XCTAssertEqual(model.deleteMenuTitle, "Delete 2 Entries…")

        // Open the folder, click the first entry, Shift+click the last: all 8 visible entries.
        model.expandedFolders = ["Project All"]
        let ids = model.visibleIDs
        XCTAssertEqual(ids.count, 8)
        model.click(ids.first!, modifiers: [])
        model.click(ids.last!, modifiers: .shift)
        XCTAssertEqual(model.listSelection.count, 8)
        var asked = 0
        model.confirmBulkDelete = { count, answer in asked = count; answer(true) }
        deleteSelected(model)
        XCTAssertEqual(asked, 8)
        XCTAssertTrue(try HistoryStore(folder: folder).entries.isEmpty)
    }

    func testOneEntryDeletesWithoutAQuestion() throws {
        let model = makeModel()
        model.search = "Other A"
        model.selectAll()
        XCTAssertEqual(model.deleteMenuTitle, "Delete")
        model.confirmBulkDelete = { _, _ in XCTFail("no question for one entry") }
        deleteSelected(model)
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 7)
    }
}

/// The root cause of the bug: Return must confirm the bulk delete question.
final class BulkDeleteAlertTests: XCTestCase {
    func testReturnDeletesAndEscapeCancels() {
        let alert = AppModel.bulkDeleteAlert(count: 6)
        alert.layout()  // NSAlert sets its key equivalents here
        XCTAssertEqual(alert.messageText, "Delete 6 entries?")
        XCTAssertEqual(alert.buttons.map(\.title), ["Delete", "Cancel"])
        XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")  // Return
        XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")  // Escape
        XCTAssertFalse(alert.buttons.contains { $0.hasDestructiveAction })  // a destructive button loses Return on macOS 26
    }
}

/// The keyboard focus of the list (the bug "after select all, delete removes only one entry"). With the search field
/// as first responder, Cmd+A selected the search text and Cmd+Delete deleted the one selected entry.
final class ListFocusTests: XCTestCase {
    var folder: URL!
    var model: AppModel!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        let store = try HistoryStore(folder: folder)
        for i in 1...6 {
            try store.add(Data("<fmxmlsnippet><Step name=\"Focus \(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS, name: "Focus \(i)")
        }
        model = AppModel(store: store, watch: false)
        model.expandedFolders = []
        model.noFolderExpanded = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFocusListTakesTheFocusFromTheSearchField() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentLayoutRect)
        let search = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 22))
        let listView = ListKeyView(frame: NSRect(x: 10, y: 50, width: 200, height: 200))
        content.addSubview(search)
        content.addSubview(listView)
        window.contentView = content
        listView.model = model
        model.listKeyView = listView

        XCTAssertTrue(window.makeFirstResponder(search))
        XCTAssertFalse(window.firstResponder === listView)
        model.focusList()
        XCTAssertTrue(window.firstResponder === listView)  // Cmd+A and Delete now go to the list
    }

    func testEditSelectAllAndEditDeleteActOnTheEntries() {
        let view = ListKeyView()
        view.model = model
        model.selection = model.visibleIDs.first  // one entry, as after a click

        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        let delete = NSMenuItem(title: "Delete", action: #selector(ListKeyView.delete(_:)), keyEquivalent: "")
        XCTAssertTrue(view.validateMenuItem(selectAll))
        XCTAssertTrue(view.validateMenuItem(delete))

        view.selectAll(nil)  // Edit > Select All, or Cmd+A
        XCTAssertEqual(model.listSelection.count, 6)
        XCTAssertEqual(model.deleteMenuTitle, "Delete 6 Entries…")

        var asked = 0
        model.confirmBulkDelete = { count, answer in asked = count; answer(true) }
        view.delete(nil)  // Edit > Delete
        XCTAssertEqual(asked, 6)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertFalse(view.validateMenuItem(delete))  // nothing selected now
        XCTAssertFalse(view.validateMenuItem(selectAll))  // nothing to select
    }
}
