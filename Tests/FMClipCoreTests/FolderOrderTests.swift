import XCTest
@testable import FMClipCore

/// The order of the folders (issue #5): HistoryStore.moveFolder, the list order, and the drop rules.
final class FolderOrderTests: XCTestCase {
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

    /// A store with the folders A, B, C, D and one entry in A, one in C and one in no folder.
    func makeStore() throws -> HistoryStore {
        let store = try HistoryStore(folder: folder)
        for name in ["A", "B", "C", "D"] { try store.makeFolder(name) }
        try store.add(xml(1), cls: .XMSS, folder: "A")
        try store.add(xml(2), cls: .XMSS, folder: "C")
        try store.add(xml(3), cls: .XMSS)
        return store
    }

    func check(_ name: String, to index: Int, gives expected: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let store = try makeStore()
        let entries = store.entries
        XCTAssertEqual(try store.moveFolder(name, to: index), expected, file: file, line: line)
        XCTAssertEqual(store.folders, expected, file: file, line: line)
        XCTAssertEqual(store.entries, entries, "the entries do not change", file: file, line: line)
        // The order is in folders.json: it stays after the store opens again.
        let again = try HistoryStore(folder: folder)
        XCTAssertEqual(again.folders, expected, file: file, line: line)
        XCTAssertEqual(again.entries, entries, file: file, line: line)
        try FileManager.default.removeItem(at: folder)
    }

    func testMoveToTheStart() throws { try check("C", to: 0, gives: ["C", "A", "B", "D"]) }
    func testMoveToTheEnd() throws { try check("A", to: 3, gives: ["B", "C", "D", "A"]) }
    func testMoveToTheMiddle() throws { try check("D", to: 1, gives: ["A", "D", "B", "C"]) }
    func testMoveDownOne() throws { try check("B", to: 2, gives: ["A", "C", "B", "D"]) }
    func testMoveOutOfRangeIsClamped() throws {
        try check("B", to: 99, gives: ["A", "C", "D", "B"])
        try check("C", to: -5, gives: ["C", "A", "B", "D"])
    }
    func testMoveToTheSamePlaceChangesNothing() throws { try check("B", to: 1, gives: ["A", "B", "C", "D"]) }
    func testNameMatchIgnoresCase() throws { try check("d", to: 0, gives: ["D", "A", "B", "C"]) }

    func testUnknownFolderIsAnError() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.moveFolder("Nope", to: 0)) {
            XCTAssertEqual($0 as? HistoryStore.FolderError, .notFound("Nope"))
        }
        XCTAssertEqual(store.folders, ["A", "B", "C", "D"])
    }

    /// A second store (another process) sees the new order after a reload.
    func testOtherStoreSeesTheOrder() throws {
        let store = try makeStore()
        let other = try HistoryStore(folder: folder)
        try store.moveFolder("D", to: 0)
        try other.reload()
        XCTAssertEqual(other.folders, ["D", "A", "B", "C"])
    }

    func testTreeRowsFollowTheNewOrder() throws {
        let store = try makeStore()
        try store.moveFolder("C", to: 0)
        let rows = HistoryTree.rows(entries: store.entries, folders: store.folders, expanded: ["C"], active: false) { _ in true }
        let c = store.entries.first { $0.folder == "C" }!.id
        let loose = store.entries.first { $0.folder == nil }!.id
        XCTAssertEqual(rows.map(\.id), ["folder:C", c, "folder:A", "folder:B", "folder:D", "no-folder", loose])
    }

    // MARK: - Pure rules

    func testMoved() {
        XCTAssertEqual(FolderOrder.moved(["A", "B", "C"], "c", to: 0), ["C", "A", "B"])
        XCTAssertEqual(FolderOrder.moved(["A", "B", "C"], "A", to: 10), ["B", "C", "A"])
        XCTAssertNil(FolderOrder.moved(["A", "B", "C"], "X", to: 0))
        XCTAssertNil(FolderOrder.moved([], "A", to: 0))
    }

    func testDropIndex() {
        let f = ["A", "B", "C", "D"]
        // Before or after another folder.
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "D", target: "B", after: false), 1)  // A D B C
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "D", target: "B", after: true), 2)   // A B D C
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "A", target: "C", after: false), 1)  // B A C D
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "A", target: "C", after: true), 2)   // B C A D
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "A", target: "D", after: true), 3)   // B C D A
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "D", target: "A", after: false), 0)  // D A B C
        // On "No Folder": last.
        XCTAssertEqual(FolderOrder.dropIndex(folders: f, dragged: "B", target: nil, after: false), 3)
        // No change: on itself, next to its place, already last, or an unknown folder.
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "B", target: "B", after: true))
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "B", target: "A", after: true))
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "B", target: "C", after: false))
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "D", target: nil, after: false))
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "X", target: "A", after: false))
        XCTAssertNil(FolderOrder.dropIndex(folders: f, dragged: "A", target: "X", after: false))
    }

    /// The drop index applied with moveFolder gives the expected order.
    func testDropIndexWithMoved() {
        let f = ["A", "B", "C", "D"]
        let i = FolderOrder.dropIndex(folders: f, dragged: "A", target: "C", after: true)!
        XCTAssertEqual(FolderOrder.moved(f, "A", to: i), ["B", "C", "A", "D"])
    }

    func testLowerHalf() {
        // A row 28 points high with 10 points of space above it: the middle is at 24.
        XCTAssertFalse(FolderOrder.isLowerHalf(y: 0, top: 10, height: 28))
        XCTAssertFalse(FolderOrder.isLowerHalf(y: 24, top: 10, height: 28))
        XCTAssertTrue(FolderOrder.isLowerHalf(y: 25, top: 10, height: 28))
        XCTAssertTrue(FolderOrder.isLowerHalf(y: 15, top: 0, height: 28))
    }

    func testDragTypeIsNotPlainText() {
        // An entry drag is plain text. The folder drag must have a different type, so a folder drop never moves entries.
        XCTAssertNotEqual(FolderOrder.dragType, "public.plain-text")
        XCTAssertNotEqual(FolderOrder.dragType, "public.utf8-plain-text")
    }
}
