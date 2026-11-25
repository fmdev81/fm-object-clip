import AppKit
import XCTest
@testable import FMClipCore
@testable import FMObjectClip

/// The settings operations of the window model: the label of the uncategorized group and the limit.
final class AppSettingsTests: XCTestCase {
    var folder: URL!
    var store: HistoryStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        store = try HistoryStore(folder: folder)
        try store.add(Data("<fmxmlsnippet><Step name=\"Keep\"/></fmxmlsnippet>".utf8), cls: .XMSS, folder: "Keep")
        for i in 1...25 {
            try store.add(Data("<fmxmlsnippet><Step name=\"Loose \(i)\"/></fmxmlsnippet>".utf8), cls: .XMSS)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNameAndLimit() {
        let model = AppModel(store: store, watch: false)
        XCTAssertEqual(model.uncategorizedName, "Uncategorized")
        model.setUncategorizedName("Inbox")
        XCTAssertEqual(model.uncategorizedName, "Inbox")
        model.setUncategorizedName("   ")
        XCTAssertEqual(model.uncategorizedName, "Uncategorized")

        XCTAssertEqual(model.uncategorizedCount, 25)
        XCTAssertEqual(model.excess(forLimit: 20), 5)
        model.setUncategorizedLimit(20)
        XCTAssertEqual(model.uncategorizedCount, 20)  // trimmed at once, and the list shows it
        XCTAssertEqual(model.entries.count, 21)
        XCTAssertEqual(SettingsStore.load(from: folder).uncategorizedLimit, 20)
    }

    func testChangeOnDiskShowsInTheModel() throws {
        let model = AppModel(store: store, watch: false)
        try SettingsStore.save(ClipSettings(appearance: "dark", uncategorizedName: "Inbox"), to: folder)  // the CLI
        model.reloadFromDisk()
        XCTAssertEqual(model.uncategorizedName, "Inbox")
        XCTAssertEqual(model.settings.appearance, "dark")
    }

    func testAppearanceValues() {
        XCTAssertNil(AppModel.nsAppearance(for: "system"))
        XCTAssertEqual(AppModel.nsAppearance(for: "light")?.name, .aqua)
        XCTAssertEqual(AppModel.nsAppearance(for: "dark")?.name, .darkAqua)
    }
}
