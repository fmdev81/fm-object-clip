import SwiftUI
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The fixes from the UI check of #3/#5: the drop operation of a group row, the limit text, and the footer path.
final class UICheckFixTests: XCTestCase {
    /// The branch of a drop comes from `hasItemsConforming(to: [.fmFolder])`: an entry drag is never a folder drop.
    func testPayloadOfDrop() {
        XCTAssertEqual(GroupDropPayload.of(hasFolderItems: true), .folder)
        XCTAssertEqual(GroupDropPayload.of(hasFolderItems: false), .entry)
    }

    /// The row feedback: a fill for an entry drag, a line for a folder drag, and nothing once the drag is not
    /// active (a late `dropUpdated` after the drop must not bring the fill back).
    func testDropFeedback() {
        var f = GroupDropPayload.feedback(.entry, active: true, after: false)
        XCTAssertTrue(f.targeted); XCTAssertNil(f.line)
        f = GroupDropPayload.feedback(.folder, active: true, after: false)
        XCTAssertFalse(f.targeted); XCTAssertEqual(f.line, .top)
        f = GroupDropPayload.feedback(.folder, active: true, after: true)
        XCTAssertFalse(f.targeted); XCTAssertEqual(f.line, .bottom)
        for payload in [GroupDropPayload.entry, .folder] {
            f = GroupDropPayload.feedback(payload, active: false, after: true)
            XCTAssertFalse(f.targeted); XCTAssertNil(f.line)
        }
    }

    func testLimitFromText() {
        XCTAssertEqual(ClipSettings.limit(fromText: "1000"), 1000)
        XCTAssertEqual(ClipSettings.limit(fromText: " 1 000 "), 1000)
        XCTAssertEqual(ClipSettings.limit(fromText: "1,000"), 1000)
        XCTAssertEqual(ClipSettings.limit(fromText: "1"), 10)  // clamped to the range
        XCTAssertEqual(ClipSettings.limit(fromText: "999999"), 100_000)
        XCTAssertNil(ClipSettings.limit(fromText: ""))
        XCTAssertNil(ClipSettings.limit(fromText: "abc"))
        XCTAssertNil(ClipSettings.limit(fromText: "10.5"))
    }

    func testFooterShortPath() {
        let home = "/Users/demo"
        XCTAssertEqual(HistoryOverrideNote.shortPath(URL(fileURLWithPath: "/Users/demo/Desktop/demo/history"), home: home),
                       "~/Desktop/demo/history")
        XCTAssertEqual(HistoryOverrideNote.shortPath(URL(fileURLWithPath: "/Users/demo"), home: home), "~")
        XCTAssertEqual(HistoryOverrideNote.shortPath(URL(fileURLWithPath: "/Users/demonstration/h"), home: home),
                       "/Users/demonstration/h")
        XCTAssertEqual(HistoryOverrideNote.shortPath(URL(fileURLWithPath: "/tmp/history"), home: home), "/tmp/history")
    }
}
