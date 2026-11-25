import XCTest
@testable import FMClipCore

final class SettingsTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func xml(_ i: Int) -> Data { Data("<fmxmlsnippet><Step name=\"Step \(i)\"/></fmxmlsnippet>".utf8) }

    func write(_ text: String) throws {
        try Data(text.utf8).write(to: SettingsStore.url(in: folder))
    }

    // MARK: - File

    func testDefaultsWhenTheFileIsMissing() {
        let s = SettingsStore.load(from: folder)
        XCTAssertEqual(s, ClipSettings())
        XCTAssertEqual(s.appearance, "system")
        XCTAssertEqual(s.uncategorizedName, "Uncategorized")
        XCTAssertEqual(s.uncategorizedLimit, 500)
    }

    func testPartialFileGivesDefaultsForTheMissingKeys() throws {
        try write(#"{"appearance": "dark", "other": 1}"#)
        XCTAssertEqual(SettingsStore.load(from: folder), ClipSettings(appearance: "dark"))
    }

    func testBadValuesGiveDefaults() throws {
        try write(#"{"appearance": "purple", "uncategorizedName": 7, "uncategorizedLimit": "many"}"#)
        XCTAssertEqual(SettingsStore.load(from: folder), ClipSettings())
    }

    func testLimitOutOfRangeIsClamped() throws {
        try write(#"{"uncategorizedLimit": 3}"#)
        XCTAssertEqual(SettingsStore.load(from: folder).uncategorizedLimit, 10)
        try write(#"{"uncategorizedLimit": 5000000}"#)
        XCTAssertEqual(SettingsStore.load(from: folder).uncategorizedLimit, 100_000)
    }

    func testUnknownFileIsNotAnError() throws {
        try write("not json")
        XCTAssertEqual(SettingsStore.load(from: folder), ClipSettings())
        try write("[1, 2]")
        XCTAssertEqual(SettingsStore.load(from: folder), ClipSettings())
    }

    func testRoundTrip() throws {
        let s = ClipSettings(appearance: "light", uncategorizedName: "Inbox", uncategorizedLimit: 1234)
        try SettingsStore.save(s, to: folder)
        XCTAssertEqual(SettingsStore.load(from: folder), s)
        XCTAssertEqual(try HistoryStore(folder: folder).settings, s)
    }

    func testBlankNameShowsTheDefault() {
        XCTAssertEqual(ClipSettings(uncategorizedName: "  ").displayName, "Uncategorized")
        XCTAssertEqual(ClipSettings(uncategorizedName: "").displayName, "Uncategorized")
        XCTAssertEqual(ClipSettings(uncategorizedName: " Inbox ").displayName, "Inbox")
    }

    // MARK: - CLI keys

    func testSetFromText() throws {
        var s = ClipSettings()
        try s.set("appearance", to: "Dark")
        try s.set("uncategorized-name", to: "  Inbox ")
        try s.set("uncategorized-limit", to: "40")
        XCTAssertEqual(s, ClipSettings(appearance: "dark", uncategorizedName: "Inbox", uncategorizedLimit: 40))
        XCTAssertEqual(ClipSettings.keys.compactMap { s.value(of: $0) }, ["dark", "Inbox", "40"])
    }

    func testSetRejectsBadKeysAndValues() {
        var s = ClipSettings()
        XCTAssertThrowsError(try s.set("color", to: "red")) {
            XCTAssertEqual($0 as? ClipSettings.SettingError, .unknownKey("color"))
        }
        XCTAssertThrowsError(try s.set("appearance", to: "purple"))
        XCTAssertThrowsError(try s.set("uncategorized-limit", to: "9"))
        XCTAssertThrowsError(try s.set("uncategorized-limit", to: "100001"))
        XCTAssertThrowsError(try s.set("uncategorized-limit", to: "ten"))
        XCTAssertEqual(s, ClipSettings())  // nothing changed
    }

    // MARK: - Limit

    func testLimitCountsOnlyUncategorizedEntries() throws {
        try SettingsStore.save(ClipSettings(uncategorizedLimit: 10), to: folder)
        let store = try HistoryStore(folder: folder)
        var foldered: [String] = []
        for i in 0..<15 { foldered.append(try store.add(xml(i), cls: .XMSS, folder: i % 2 == 0 ? "A" : "B").id) }
        var loose: [String] = []
        for i in 100..<113 { loose.append(try store.add(xml(i), cls: .XMSS).id) }  // N + 3

        XCTAssertEqual(store.uncategorizedCount, 10)
        XCTAssertEqual(store.query(scope: .none).map(\.id), loose.suffix(10).reversed())  // the newest 10
        XCTAssertEqual(Set(store.entries.filter { $0.folder != nil }.map(\.id)), Set(foldered))  // all foldered stay
        XCTAssertEqual(store.entries.count, 25)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".xml") }
        XCTAssertEqual(files.count, 25)
    }

    func testLowerLimitTrimsAtOnce() throws {
        let store = try HistoryStore(folder: folder)
        let kept = try store.add(xml(0), cls: .XMSS, folder: "Keep")
        var loose: [String] = []
        for i in 1...30 { loose.append(try store.add(xml(i), cls: .XMSS).id) }
        XCTAssertEqual(store.excess(forLimit: 12), 18)
        XCTAssertEqual(store.excess(forLimit: 40), 0)

        let gone = try store.updateSettings { $0.uncategorizedLimit = 12 }
        XCTAssertEqual(Set(gone.map(\.id)), Set(loose.prefix(18)))
        XCTAssertEqual(store.uncategorizedCount, 12)
        XCTAssertNotNil(store.entry(id: kept.id))
        XCTAssertEqual(store.settings.uncategorizedLimit, 12)
        XCTAssertEqual(store.limit, 12)

        // The change is on disk: a second store (the CLI or the app) sees it.
        let other = try HistoryStore(folder: folder)
        XCTAssertEqual(other.entries.count, 13)
        XCTAssertEqual(other.limit, 12)

        // A higher limit deletes nothing.
        XCTAssertTrue(try store.updateSettings { $0.uncategorizedLimit = 50 }.isEmpty)
    }

    func testLimitFromAnotherProcessAppliesAtTheNextCapture() throws {
        let store = try HistoryStore(folder: folder)
        for i in 0..<15 { try store.add(xml(i), cls: .XMSS) }
        try SettingsStore.save(ClipSettings(uncategorizedLimit: 10), to: folder)  // for example the CLI
        try store.add(xml(99), cls: .XMSS)
        XCTAssertEqual(store.uncategorizedCount, 10)
    }

    func testOtherSettingsDoNotTrim() throws {
        let store = try HistoryStore(folder: folder, limit: 10)
        for i in 0..<10 { try store.add(xml(i), cls: .XMSS) }
        XCTAssertTrue(try store.updateSettings { $0.appearance = "dark"; $0.uncategorizedName = "Inbox" }.isEmpty)
        XCTAssertEqual(store.entries.count, 10)
        XCTAssertEqual(store.settings.appearance, "dark")
    }
}
