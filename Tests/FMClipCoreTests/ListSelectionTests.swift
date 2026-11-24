import XCTest
@testable import FMClipCore

final class ListSelectionTests: XCTestCase {
    let order = ["a", "b", "c", "d", "e"]

    func testClickAndCmdClick() {
        var s = ListSelection()
        s.select("b")
        XCTAssertEqual(s.ids, ["b"])
        XCTAssertEqual(s.single, "b")
        s.toggle("d", order: order)
        XCTAssertEqual(s.ids, ["b", "d"])
        XCTAssertNil(s.single)  // more than one: no single entry
        s.toggle("b", order: order)
        XCTAssertEqual(s.ids, ["d"])
        s.toggle("d", order: order)
        XCTAssertTrue(s.isEmpty)
    }

    func testShiftClickSelectsARangeInTheVisibleOrder() {
        var s = ListSelection()
        s.select("b")
        s.extend(to: "d", order: order)
        XCTAssertEqual(s.ids, ["b", "c", "d"])
        s.extend(to: "a", order: order)  // from the same anchor, the other way
        XCTAssertEqual(s.ids, ["a", "b"])
        var none = ListSelection()
        none.extend(to: "c", order: order)  // no anchor: a click
        XCTAssertEqual(none.ids, ["c"])
    }

    func testShiftArrowsExtendAndShrink() {
        var s = ListSelection()
        s.move(by: 1, extend: false, order: order)
        XCTAssertEqual(s.ids, ["a"])
        s.move(by: 1, extend: true, order: order)
        s.move(by: 1, extend: true, order: order)
        XCTAssertEqual(s.ids, ["a", "b", "c"])
        s.move(by: -1, extend: true, order: order)
        XCTAssertEqual(s.ids, ["a", "b"])
        s.move(by: 1, extend: false, order: order)  // a plain arrow selects one entry again
        XCTAssertEqual(s.ids, ["c"])
        s.move(by: 9, extend: false, order: order)
        XCTAssertEqual(s.ids, ["e"])  // stops at the end
    }

    func testSelectAllAndPrune() {
        var s = ListSelection()
        s.selectAll(order: order)
        XCTAssertEqual(s.count, 5)
        s.prune(visible: ["b", "d"])  // a filter or a collapse hides the others
        XCTAssertEqual(s.ids, ["b", "d"])
        s.prune(visible: [])
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.anchor)
        var empty = ListSelection()
        empty.selectAll(order: [])
        XCTAssertTrue(empty.isEmpty)
    }
}
