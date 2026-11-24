import XCTest
@testable import FMClipCore

final class LimitTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func xmlFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".xml") }
    }

    func testSameDataTwoTimesGivesOneEntryAtTheTop() throws {
        let store = try HistoryStore(folder: folder)
        let steps = Samples.data(for: .XMSS)
        let first = try store.add(steps, cls: .XMSS, now: Date(timeIntervalSince1970: 1000))
        try store.add(Samples.data(for: .XMTB), cls: .XMTB)
        let again = try store.add(steps, cls: .XMSS, now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(store.entries.map(\.cls), [.XMSS, .XMTB])
        XCTAssertNotEqual(store.entries[0].time, first.time)
        XCTAssertEqual(try xmlFiles().count, 2)
    }

    func testSameDataWithTwoClassesGivesTwoEntries() throws {
        let store = try HistoryStore(folder: folder)
        let data = Samples.data(for: .XMFD)
        try store.add(data, cls: .XMFD)
        try store.add(data, cls: .XMTB)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testLimitIs200() {
        XCTAssertEqual(HistoryStore.maxEntries, 200)
    }

    func testOldestEntryGoesAfter201Captures() throws {
        let store = try HistoryStore(folder: folder)
        var ids: [String] = []
        for i in 0...HistoryStore.maxEntries {
            ids.append(try store.add(Data("<fmxmlsnippet><Step name=\"Step \(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS).id)
        }
        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(try xmlFiles().count, 200)
        XCTAssertNil(store.entry(id: ids[0]))
        XCTAssertNotNil(store.entry(id: ids[1]))
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 200)
    }

    func testRepairAtOpen() throws {
        let store = try HistoryStore(folder: folder)
        let gone = try store.add(Samples.data(for: .XMSS), cls: .XMSS)
        let kept = try store.add(Samples.data(for: .XML2), cls: .XML2)
        try FileManager.default.removeItem(at: store.fileURL(for: gone))
        try Data("<x/>".utf8).write(to: folder.appendingPathComponent("stray.xml"))

        let again = try HistoryStore(folder: folder)
        XCTAssertEqual(again.entries.map(\.id), [kept.id])
        XCTAssertEqual(again.repairLog, ["removed 1 index entries with no .xml file", "ignored stray.xml: no index entry"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("stray.xml").path))
    }
}
