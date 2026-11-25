import XCTest
@testable import FMClipCore

/// The `-HistoryFolder PATH` launch argument: the folder resolution is a pure function.
final class HistoryFolderOverrideTests: XCTestCase {
    func resolve(_ value: String?) -> String? {
        HistoryStore.folder(override: value, home: "/Users/demo", currentDirectory: "/work")?.path
    }

    func testAbsentOrEmptyGivesNil() {
        XCTAssertNil(resolve(nil))
        XCTAssertNil(resolve(""))
        XCTAssertNil(resolve("   "))
    }

    func testTildeIsHome() {
        XCTAssertEqual(resolve("~/Desktop/demo-history"), "/Users/demo/Desktop/demo-history")
        XCTAssertEqual(resolve("~"), "/Users/demo")
    }

    func testAbsolutePath() {
        XCTAssertEqual(resolve("/tmp/demo/history"), "/tmp/demo/history")
        XCTAssertEqual(resolve("/tmp/demo/history/"), "/tmp/demo/history")
        XCTAssertEqual(resolve(" /tmp/demo/../demo2/history "), "/tmp/demo2/history")
    }

    func testRelativePathUsesCurrentDirectory() {
        XCTAssertEqual(resolve("demo-history"), "/work/demo-history")
    }

    func testTheKeyIsHistoryFolder() {
        XCTAssertEqual(HistoryStore.folderOverrideKey, "HistoryFolder")
    }
}
