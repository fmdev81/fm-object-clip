import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// PortalCheck: a portal child must be in the first portal row, with bounds relative to the portal.
final class PortalCheckTests: XCTestCase {
    /// A portal at 112,20,292,740 with 6 rows of 30, and one field with the given bounds.
    func clip(_ top: String, _ left: String, _ bottom: String, _ right: String) -> Data {
        Data("""
        <fmxmlsnippet type="LayoutObjectList"><Layout>
        <Object type="Portal" key="1" name="portal_one"><Bounds top="112" left="20" bottom="292" right="740"/>
        <PortalObj numOfRows="6"><TableAliasKey>Contacts</TableAliasKey>
        <Object type="Field" key="2"><Bounds top="\(top)" left="\(left)" bottom="\(bottom)" right="\(right)"/>
        <FieldObj><Name>Contacts::Company</Name></FieldObj></Object>
        </PortalObj></Object></Layout></fmxmlsnippet>
        """.utf8)
    }

    func testGoodChildPasses() {
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("4", "4", "24", "214")), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("4.5", "4", "24.25", "214")), [])
        XCTAssertNil(PortalCheck.message(cls: .XML2, data: clip("4", "4", "24", "214")))
    }

    func testChildOutsideRowOne() {
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: clip("116", "24", "136", "234")), [
            "portal portal_one: Field Contacts::Company at 116,24,136,234 "
            + "is outside the first row of the portal (0,0,30,720; 6 rows)",
        ])
        let message = PortalCheck.message(cls: .XML2, data: clip("116", "24", "136", "234")) ?? ""
        XCTAssertTrue(message.hasPrefix("1 portal children are in the wrong place:\n  portal portal_one:"), message)
    }

    func testChildOutsideThePortal() {
        for b in [("348", "24", "368", "64"), ("4", "694", "24", "754"), ("-2", "4", "18", "214")] {
            let problems = PortalCheck.problems(cls: .XML2, data: clip(b.0, b.1, b.2, b.3))
            XCTAssertEqual(problems.count, 1)
            XCTAssertTrue(problems[0].hasSuffix("is outside the portal (0,0,180,720)"), problems[0])
        }
    }

    func testOtherClassesAndBadXMLPass() {
        XCTAssertEqual(PortalCheck.problems(cls: .XMSS, data: clip("116", "24", "136", "234")), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: Data("<fmxmlsnippet".utf8)), [])
        XCTAssertEqual(PortalCheck.problems(cls: .XML2, data: Samples.data(for: .XML2)), [])
    }

    /// Copy Entry in the window: a bad layout entry stays off the clipboard, with an error; a good one is copied.
    func testCopyEntryRefusesABadPortal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(folder: folder)
        let bad = try store.add(clip("116", "24", "136", "234"), cls: .XML2, name: "bad")
        let good = try store.add(clip("4", "4", "24", "214"), cls: .XML2, name: "good")
        let model = AppModel(store: store, watch: false)
        let board = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let before = board.changeCount

        model.copy(bad, to: board)
        XCTAssertEqual(board.changeCount, before)
        XCTAssertTrue(model.errorMessage?.contains("outside the first row") == true, model.errorMessage ?? "nil")
        XCTAssertNil(store.lastRestore())

        model.errorMessage = nil
        model.copy(good, to: board)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotEqual(board.changeCount, before)
    }
}
