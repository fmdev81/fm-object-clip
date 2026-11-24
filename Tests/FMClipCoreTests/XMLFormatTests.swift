import AppKit
import XCTest
@testable import FMClipCore

final class XMLFormatTests: XCTestCase {
    func text(_ cls: FMClass) throws -> String {
        String(decoding: Samples.data(for: cls), as: UTF8.self)
    }

    func testCompactXMLIsIndented() throws {
        let raw = try text(.XMFD)
        XCTAssertEqual(raw.split(separator: "\n").count, 1)  // the sample has the fields on one line
        let lines = XMLFormat.pretty(raw).components(separatedBy: "\n")
        XCTAssertGreaterThan(lines.count, 20)
        XCTAssertEqual(lines[0], #"<fmxmlsnippet type="FMObjectList">"#)
        XCTAssertTrue(lines[1].hasPrefix(#"  <Field id="1" dataType="Text""#))
        XCTAssertTrue(lines.contains(#"    <Calculation><![CDATA[First Name & " " & Last Name]]></Calculation>"#))
        XCTAssertTrue(lines.contains("    <Comment>Given name</Comment>"))
        XCTAssertTrue(lines.contains(#"      <NotEmpty value="True"></NotEmpty>"#))
        XCTAssertEqual(lines.last, "</fmxmlsnippet>")
    }

    func testFormatKeepsTheContent() throws {
        for cls in [FMClass.XMFD, .XMTB] {
            let raw = try text(cls)
            let squash = { (s: String) in s.filter { !$0.isWhitespace } }
            XCTAssertEqual(squash(XMLFormat.pretty(raw)), squash(raw), "\(cls)")
        }
    }

    func testFormatIsStable() throws {
        for cls in FMClass.allCases {
            let once = XMLFormat.pretty(try text(cls))
            XCTAssertEqual(XMLFormat.pretty(once), once, "\(cls)")
        }
    }

    func testLeafTextStaysAsCaptured() throws {
        let lines = XMLFormat.pretty(try text(.XMSS)).components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("    <Text>PURPOSE: count the contacts with no e-mail address</Text>"))
        XCTAssertEqual(lines[0], #"<?xml version="1.0" encoding="UTF-8"?>"#)
    }

    func testBadXMLDoesNotStopTheFormatter() {
        XCTAssertEqual(XMLFormat.pretty("<a><b x=\"1>"), "<a>\n  <b x=\"1>")
        XCTAssertEqual(XMLFormat.pretty(""), "")
        XCTAssertEqual(XMLFormat.pretty("plain"), "plain")
    }

    func testHighlightCoversAllTheText() throws {
        for cls in FMClass.allCases {
            let s = XMLFormat.pretty(try text(cls))
            XCTAssertEqual(XMLFormat.highlight(s).map { String($0.1) }.joined(), s, "\(cls)")
        }
    }

    func testHighlightKinds() {
        let parts = XMLFormat.highlight(#"<!-- c --><Step enable="True"><Calc><![CDATA[1 > 0]]></Calc>t</Step><B/>"#)
        let got = parts.map { ($0.0, String($0.1)) }
        let want: [(XMLSyntax, String)] = [
            (.comment, "<!-- c -->"), (.tag, "<Step"), (.plain, " "), (.attributeName, "enable"), (.plain, "="),
            (.attributeValue, "\"True\""), (.tag, ">"), (.tag, "<Calc"), (.tag, ">"), (.cdata, "<![CDATA[1 > 0]]>"),
            (.tag, "</Calc>"), (.text, "t"), (.tag, "</Step>"), (.tag, "<B"), (.tag, "/>"),
        ]
        XCTAssertEqual(got.map(\.0), want.map(\.0))
        XCTAssertEqual(got.map(\.1), want.map(\.1))
    }
}

final class CopyTests: XCTestCase {
    func testCopyKeepsTheOriginalBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fm-object-clip-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("fm-object-clip-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let store = try HistoryStore(folder: folder)
        for cls in FMClass.allCases {
            let original = Samples.data(for: cls)
            let entry = try store.add(original, cls: cls)
            // The view formats the XML. That must not change the stored bytes or the copied bytes.
            let shown = XMLFormat.pretty(String(decoding: try store.data(for: entry), as: UTF8.self))
            XCTAssertNotEqual(Data(shown.utf8), original, "\(cls)")
            XCTAssertNotNil(try store.copy(entry, to: pasteboard))
            XCTAssertEqual(FMPasteboard.read(pasteboard), [FMObject(cls: cls, data: original)], "\(cls)")
            XCTAssertEqual(try Data(contentsOf: store.fileURL(for: entry)), original, "\(cls)")
        }
    }
}
