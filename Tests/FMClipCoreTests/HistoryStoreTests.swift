import XCTest
@testable import FMClipCore

final class HistoryStoreTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        // A temporary folder. The tests never use the real history folder.
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAddWritesFileAndIndex() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMSS)
        let e = try store.add(data, cls: .XMSS)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("\(e.id).xml")), data)  // byte for byte
        XCTAssertEqual(e.source, "clipboard")
        XCTAssertEqual(e.sha256.count, 64)

        let index = (try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("index.json"))) as! [[String: Any]]).map { $0.mapValues { "\($0)" } }
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(Set(index[0].keys), ["id", "class", "time", "title", "titleVersion", "sha256", "source", "canonical"])
        XCTAssertEqual(index[0]["class"], "XMSS")
    }

    func testReopenAndOrder() throws {
        let store = try HistoryStore(folder: folder)
        let a = try store.add(Samples.data(for: .XMTB), cls: .XMTB)
        let b = try store.add(Samples.data(for: .XML2), cls: .XML2)
        let again = try HistoryStore(folder: folder)
        XCTAssertEqual(again.entries.map(\.id), [b.id, a.id])
        XCTAssertEqual(try again.data(for: again.entries[1]), Samples.data(for: .XMTB))
    }

    func testDelete() throws {
        let store = try HistoryStore(folder: folder)
        let e = try store.add(Samples.data(for: .XMFD), cls: .XMFD)
        try store.delete(id: e.id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: e).path))
        XCTAssertTrue(try HistoryStore(folder: folder).entries.isEmpty)
    }

    func testTitles() throws {
        let t = { (cls: FMClass) in Titles.title(for: cls, data: Samples.data(for: cls), time: "T") }
        XCTAssertEqual(t(.XMSS), "# PURPOSE: count the contacts with no e-mail address (11 steps)")
        XCTAssertEqual(t(.XMTB), "Contacts, Email Addresses")
        XCTAssertEqual(t(.XMFD), "First Name, Last Name, Created, … (4 fields)")
        XCTAssertEqual(t(.XML2), "4 layout objects")
    }

    func testLongCommentTitleIsCut() {
        let comment = String(repeating: "abcdefghij", count: 7)  // 70 characters
        let xml = ##"<fmxmlsnippet type="FMObjectList"><Step enable="True" id="89" name="# (comment)"><Text>"## + comment + "</Text></Step></fmxmlsnippet>"
        XCTAssertEqual(Titles.title(for: .XMSS, data: Data(xml.utf8), time: "T"), "# " + String(comment.prefix(60)) + "… (1 step)")
    }

    func testCommentTitleHasOneLine() {
        let xml = ##"<fmxmlsnippet type="FMObjectList"><Step enable="True" id="89" name="# (comment)"><Text>&#10;  First line&#10;second line</Text></Step></fmxmlsnippet>"##
        XCTAssertEqual(Titles.title(for: .XMSS, data: Data(xml.utf8), time: "T"), "# First line (1 step)")
    }

    func testBadXMLDoesNotStopTheStore() throws {
        let store = try HistoryStore(folder: folder)
        let bad = try store.add(Data("<fmxmlsnippet><Step".utf8), cls: .XMSS)
        XCTAssertEqual(bad.title, "XMSS \(bad.time)")
        let empty = try store.add(Data(), cls: .XMFD)
        XCTAssertEqual(empty.title, "XMFD \(empty.time)")
        XCTAssertEqual(store.entries.count, 2)
    }
}
