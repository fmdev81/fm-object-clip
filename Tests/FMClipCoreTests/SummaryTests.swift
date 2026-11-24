import XCTest
@testable import FMClipCore

final class SummaryTests: XCTestCase {
    func summary(_ cls: FMClass) throws -> [String] {
        try XCTUnwrap(Summary.summary(for: cls, data: Samples.data(for: cls))).components(separatedBy: "\n")
    }

    func testSteps() throws {
        XCTAssertEqual(try summary(.XMSS), [
            "# PURPOSE: count the contacts with no e-mail address",
            "Set Error Capture",
            "Set Variable [ $count … ]",
            "Go to Record/Request/Page",
            "Loop",
            "    If [ IsEmpty ( Contacts::Email ) … ]",  // the steps in a block have an indent
            "        Set Variable [ $count … ]",
            "    End If",
            "    Go to Record/Request/Page",
            "End Loop",
            #"Show Custom Dialog [ "Contacts" … ]"#,  // the first line of the first calc
        ])
    }

    func testDisabledStep() {
        let xml = #"<fmxmlsnippet type="FMObjectList"><Step enable="False" id="141" name="Set Variable"/><Step enable="True" id="1" name="Beep"/></fmxmlsnippet>"#
        XCTAssertEqual(Summary.summary(for: .XMSS, data: Data(xml.utf8)), "// Set Variable\nBeep")
    }

    func testTables() throws {
        XCTAssertEqual(try summary(.XMTB), [
            "Table: Contacts (2 fields)",
            "    First Name — Text; validation (NotEmpty)",
            "    Last Name — Text",
            "Table: Email Addresses (2 fields)",
            "    Address — Text",
            "    Contact ID — Number",
        ])
    }

    func testFields() throws {
        XCTAssertEqual(try summary(.XMFD), [
            "First Name — Text; validation (NotEmpty)",
            "Last Name — Text",
            "Created — TimeStamp; auto-enter CreationTimeStamp",
            "Full Name — Text; calculation",
        ])
    }

    func testFieldOptions() {
        let xml = #"<fmxmlsnippet type="FMObjectList"><Field id="1" dataType="Number" fieldType="Normal" name="ID"><AutoEnter calculation="True" constant="False" lookup="False"><Calculation><![CDATA[Get ( UUIDNumber )]]></Calculation></AutoEnter><Validation message="False" maxLength="False" valuelist="False" calculation="False"><NotEmpty value="True"/><Unique value="True"/></Validation></Field><Field id="2" dataType="Number" fieldType="Summary" name="Count"/></fmxmlsnippet>"#
        XCTAssertEqual(Summary.summary(for: .XMFD, data: Data(xml.utf8)),
                       "ID — Number; auto-enter calculation; validation (NotEmpty, Unique)\nCount — Number; summary")
    }

    func testLayout() throws {
        XCTAssertEqual(try summary(.XML2), ["Field: 2", "Text: 2", "", "Fields:", "    Contacts::First Name", "    Contacts::Last Name"])
    }

    func testBadXMLGivesNoSummary() {
        XCTAssertNil(Summary.summary(for: .XMSS, data: Data("<fmxmlsnippet><Step".utf8)))
        XCTAssertNil(Summary.summary(for: .XML2, data: Data()))
        XCTAssertNil(Summary.summary(for: .XMTB, data: Data("<fmxmlsnippet/>".utf8)))
    }
}
