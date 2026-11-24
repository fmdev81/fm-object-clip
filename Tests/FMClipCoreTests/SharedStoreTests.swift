import XCTest
@testable import FMClipCore

/// Two store instances on the same folder, like the app (open all the time) and fm-object-clip-cli.
final class SharedStoreTests: XCTestCase {
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

    func testCLIChangeWhileTheAppIsOpenIsNotLost() throws {
        let app = try HistoryStore(folder: folder)
        let a = try app.add(xml(1), cls: .XMSS)
        let b = try app.add(xml(2), cls: .XMSS)

        // The CLI changes the history while the app instance is open, with old data in memory.
        let cli = try HistoryStore(folder: folder)
        try cli.rename(id: a.id, to: "Renamed by CLI")
        try cli.move(id: b.id, to: "CLI Project")
        let c = try cli.add(xml(3), cls: .XMSS, name: "Added by CLI")
        try cli.makeFolder("Empty CLI folder")

        // The app writes next. It reads the latest state first, so the CLI changes stay.
        let d = try app.add(xml(4), cls: .XMSS, name: "Added by app")
        XCTAssertEqual(app.entry(id: a.id)?.name, "Renamed by CLI")
        XCTAssertEqual(app.entry(id: b.id)?.folder, "CLI Project")
        XCTAssertNotNil(app.entry(id: c.id))
        XCTAssertNotNil(app.entry(id: d.id))
        XCTAssertEqual(app.folders, ["CLI Project", "Empty CLI folder"])

        // A third instance reads all the changes from disk.
        let fresh = try HistoryStore(folder: folder)
        XCTAssertEqual(Set(fresh.entries.map(\.id)), [a.id, b.id, c.id, d.id])
        XCTAssertEqual(fresh.entry(id: a.id)?.name, "Renamed by CLI")
        XCTAssertEqual(fresh.folders, ["CLI Project", "Empty CLI folder"])
    }

    func testAppChangeAfterCLIDeleteDoesNotBringTheEntryBack() throws {
        let app = try HistoryStore(folder: folder)
        let a = try app.add(xml(1), cls: .XMSS)
        let b = try app.add(xml(2), cls: .XMSS)
        let cli = try HistoryStore(folder: folder)
        XCTAssertEqual(try cli.delete(ids: [a.id]).map(\.id), [a.id])
        try app.rename(id: b.id, to: "Renamed by app")
        let fresh = try HistoryStore(folder: folder)
        XCTAssertEqual(fresh.entries.map(\.id), [b.id])
        XCTAssertEqual(fresh.entries[0].name, "Renamed by app")
    }

    func testManyWritersAtTheSameTime() throws {
        _ = try HistoryStore(folder: folder)
        let group = DispatchGroup()
        let errors = NSMutableArray()
        for i in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let store = try HistoryStore(folder: self.folder)
                    try store.add(self.xml(i), cls: .XMSS, folder: i.isMultiple(of: 2) ? "Even" : nil)
                } catch {
                    errors.add(error)
                }
            }
        }
        group.wait()
        XCTAssertEqual(errors.count, 0)
        let fresh = try HistoryStore(folder: folder)
        XCTAssertEqual(fresh.entries.count, 20)  // no capture is lost
        XCTAssertEqual(fresh.count(in: "Even"), 10)
    }

    func testReloadSeesAChangeFromAnotherInstance() throws {
        let app = try HistoryStore(folder: folder)
        let cli = try HistoryStore(folder: folder)
        let e = try cli.add(xml(1), cls: .XMSS)
        XCTAssertNil(app.entry(id: e.id))
        try app.reload()
        XCTAssertNotNil(app.entry(id: e.id))
    }

    func testInsertPutsBackADeletedEntry() throws {
        let store = try HistoryStore(folder: folder)
        let old = try store.add(xml(1), cls: .XMSS, folder: "Gone soon", now: Date(timeIntervalSince1970: 1000))
        try store.add(xml(2), cls: .XMSS, now: Date(timeIntervalSince1970: 3000))
        let data = try store.data(for: old)
        try store.delete(id: old.id)
        try store.deleteFolder("Gone soon")
        try store.add(xml(3), cls: .XMSS, now: Date(timeIntervalSince1970: 2000))

        try store.insert(old, data: data)
        XCTAssertEqual(store.entries.last?.id, old.id)  // back in its place by time
        XCTAssertEqual(store.entry(id: old.id)?.folder, "Gone soon")
        XCTAssertEqual(store.folders, ["Gone soon"])  // the folder is back
        XCTAssertEqual(try store.data(for: old), data)
        try store.insert(old, data: data)  // a second insert does nothing
        XCTAssertEqual(store.entries.count, 3)
    }

    func testDeleteManyAndQuery() throws {
        let store = try HistoryStore(folder: folder)
        let a = try store.add(xml(1), cls: .XMSS, name: "Invoice steps", folder: "Project A")
        let b = try store.add(Samples.data(for: .XMFD), cls: .XMFD, folder: "project a")
        let c = try store.add(Samples.data(for: .XML2), cls: .XML2)
        XCTAssertEqual(Set(store.query(scope: .folder("Project A")).map(\.id)), [a.id, b.id])
        XCTAssertEqual(store.query(scope: .none).map(\.id), [c.id])
        XCTAssertEqual(store.query(cls: .XMFD).map(\.id), [b.id])
        XCTAssertEqual(store.query(search: "invoice").map(\.id), [a.id])  // name, any case
        XCTAssertEqual(store.query(search: "Contacts::First Name").map(\.id), [c.id])  // XML text
        XCTAssertEqual(store.query(limit: 2).count, 2)
        XCTAssertEqual(Set(try store.delete(ids: [a.id, c.id, "no-such-id"]).map(\.id)), [a.id, c.id])
        XCTAssertEqual(store.entries.map(\.id), [b.id])
    }

    func testFolderWatcherSeesAWrite() throws {
        let store = try HistoryStore(folder: folder)
        let changed = expectation(description: "change")
        changed.assertForOverFulfill = false
        let watcher = HistoryFolderWatcher(folder: folder, delay: 0.05) { changed.fulfill() }
        XCTAssertNotNil(watcher)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            _ = try? HistoryStore(folder: self.folder).add(self.xml(1), cls: .XMSS)
        }
        wait(for: [changed], timeout: 5)
        _ = store
    }
}

final class BulkStoreTests: XCTestCase {
    func testBulkDeleteMoveAndUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(folder: folder)
        var ids: [String] = []
        for i in 0..<5 {
            ids.append(try store.add(Data("<fmxmlsnippet><Step name=\"S\(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS,
                                     now: Date(timeIntervalSince1970: Double(1000 + i))).id)
        }
        let moved = try store.move(ids: [ids[0], ids[2], "nope"], to: "Project Multi")
        XCTAssertEqual(Set(moved.map(\.id)), [ids[0], ids[2]])
        XCTAssertEqual(store.count(in: "Project Multi"), 2)

        let items = try [ids[1], ids[2], ids[3]].map { id -> (HistoryEntry, Data) in
            let e = store.entry(id: id)!
            return (e, try store.data(for: e))
        }
        try store.delete(ids: [ids[1], ids[2], ids[3]])
        try store.deleteFolder("Project Multi")
        XCTAssertEqual(store.entries.count, 2)

        try store.insert(items)  // Undo of the bulk delete, in one change
        XCTAssertEqual(store.entries.map(\.id), ids.reversed())  // back in the order by time
        XCTAssertEqual(store.entry(id: ids[2])?.folder, "Project Multi")
        XCTAssertEqual(store.folders, ["Project Multi"])
        XCTAssertEqual(try HistoryStore(folder: folder).entries.count, 5)
    }
}
