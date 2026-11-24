import XCTest
@testable import FMClipCore

final class ShortTimeTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()
    let locale = Locale(identifier: "en_US")

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func format(_ d: Date) -> String {
        ShortTime.format(d, now: date(2026, 11, 20, 15, 0), calendar: calendar, locale: locale)
    }

    func testToday() {
        XCTAssertEqual(format(date(2026, 11, 20, 9, 5)).replacingOccurrences(of: "\u{202F}", with: " "), "9:05 AM")
    }

    func testYesterday() {
        XCTAssertEqual(format(date(2026, 11, 19, 23, 59)), "Yesterday")
        XCTAssertEqual(format(date(2026, 11, 19, 0, 1)), "Yesterday")
    }

    func testThisYear() {
        XCTAssertEqual(format(date(2026, 11, 18)), "Nov 18")
        XCTAssertEqual(format(date(2026, 1, 2)), "Jan 2")
    }

    func testEarlierYear() {
        XCTAssertEqual(format(date(2025, 11, 18)), "Nov 18, 2025")
    }

    func testParse() {
        XCTAssertNotNil(ShortTime.parse("2026-11-20T17:21:29.755Z"))
        XCTAssertNotNil(ShortTime.parse("2026-11-20T17:21:29Z"))
        XCTAssertNil(ShortTime.parse("not a time"))
    }
}
