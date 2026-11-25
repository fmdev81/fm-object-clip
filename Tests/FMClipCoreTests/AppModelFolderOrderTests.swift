import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// Move Folder in the window model (issue #5): the new order, the context menu steps, and Undo.
final class AppModelFolderOrderTests: XCTestCase {
    var folder: URL!

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testMoveFolderUndoRedo() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        let store = try HistoryStore(folder: folder)
        for name in ["A", "B", "C"] { try store.makeFolder(name) }
        let e = try store.add(Data("<fmxmlsnippet><Step name=\"x\"/></fmxmlsnippet>".utf8), cls: .XMSS, folder: "B")
        let undo = UndoManager()
        undo.groupsByEvent = false
        let model = AppModel(store: store, watch: false)
        model.undoManager = undo

        undo.beginUndoGrouping()
        model.moveFolder("C", to: 0)  // a drop, or Move Folder Up two times
        undo.endUndoGrouping()
        XCTAssertEqual(model.folders, ["C", "A", "B"])
        XCTAssertEqual(store.entry(id: e.id)?.folder, "B")
        XCTAssertEqual(undo.undoActionName, "Move Folder")

        undo.undo()
        XCTAssertEqual(model.folders, ["A", "B", "C"])
        XCTAssertEqual(try HistoryStore(folder: folder).folders, ["A", "B", "C"])
        undo.redo()
        XCTAssertEqual(model.folders, ["C", "A", "B"])

        // A move to the same place registers no Undo (out of a group, a registration would raise an exception).
        undo.removeAllActions()
        model.moveFolder("C", to: -1)
        XCTAssertEqual(model.folders, ["C", "A", "B"])
        XCTAssertFalse(undo.canUndo)
    }
}
