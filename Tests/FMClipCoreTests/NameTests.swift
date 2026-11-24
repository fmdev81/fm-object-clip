import AppKit
import XCTest
@testable import FMClipCore

final class NameTests: XCTestCase {
    var folder: URL!
    var pasteboard: NSPasteboard!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        pasteboard.releaseGlobally()
    }

    func indexItems() throws -> [[String: String]] {
        (try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("index.json"))) as! [[String: Any]]).map { $0.mapValues { "\($0)" } }
    }

    func testAddWithName() throws {
        let data = Samples.data(for: .XMSS)
        let store = try HistoryStore(folder: folder)
        let e = try store.add(data, cls: .XMSS, name: "  Count contacts – no email \n")
        XCTAssertEqual(e.name, "Count contacts – no email")  // trimmed
        XCTAssertEqual(e.displayTitle, "Count contacts – no email")
        XCTAssertTrue(e.title.hasPrefix("# PURPOSE"))  // the automatic title stays
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: e)), data)  // the name does not change the bytes
        XCTAssertEqual(try indexItems()[0]["name"], "Count contacts – no email")
        XCTAssertEqual(try HistoryStore(folder: folder).entries[0].name, "Count contacts – no email")
    }

    func testAddWithoutName() throws {
        let store = try HistoryStore(folder: folder)
        let e = try store.add(Samples.data(for: .XML2), cls: .XML2, name: "   ")  // an empty name is no name
        XCTAssertNil(e.name)
        XCTAssertEqual(e.displayTitle, "4 layout objects")
        XCTAssertNil(try indexItems()[0]["name"])
    }

    func testSameXMLWithNewNameUpdatesTheName() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMFD)
        let first = try store.add(data, cls: .XMFD, name: "Fields v1")
        try store.add(Samples.data(for: .XMTB), cls: .XMTB)
        let again = try store.add(data, cls: .XMFD, name: "Fields v2")
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].id, first.id)  // moved to the top
        XCTAssertEqual(store.entries[0].name, "Fields v2")

        // A capture with no name keeps the name.
        try store.add(data, cls: .XMFD, name: nil)
        XCTAssertEqual(store.entries[0].name, "Fields v2")
        XCTAssertEqual(store.entries.count, 2)
    }

    func testRename() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMTB)
        let e = try store.add(data, cls: .XMTB)
        XCTAssertEqual(try store.rename(id: e.id, to: " Contact tables ")?.displayTitle, "Contact tables")
        XCTAssertEqual(try HistoryStore(folder: folder).entries[0].name, "Contact tables")
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: e)), data)

        XCTAssertEqual(try store.rename(id: e.id, to: "")?.displayTitle, "Contacts, Email Addresses")
        XCTAssertNil(try HistoryStore(folder: folder).entries[0].name)
        XCTAssertNil(try store.rename(id: "no-such-id", to: "x"))
    }

    func testCopyPutsOnlyTheFileMakerClass() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMSS)
        let e = try store.add(data, cls: .XMSS, name: "Named steps")
        try store.copy(e, to: pasteboard)
        XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: .XMSS, data: data)])
        XCTAssertEqual(pasteboard.data(forType: FMClass.XMSS.pasteboardType), data)
    }
}
