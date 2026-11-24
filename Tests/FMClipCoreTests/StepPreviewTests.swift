import XCTest
@testable import FMClipCore

/// The script preview: one short line for each step, from a generic read of the XML. Fake names only.
final class StepPreviewTests: XCTestCase {
    func preview(_ steps: String) -> String? {
        Summary.summary(for: .XMSS, data: Data("<fmxmlsnippet type=\"FMObjectList\">\(steps)</fmxmlsnippet>".utf8))
    }

    let setField = #"<Step enable="True" id="76" name="Set Field"><Calculation><![CDATA[$name]]></Calculation><Field table="Contacts" id="2" name="Company"/></Step>"#
    let setVariable = #"<Step enable="True" id="141" name="Set Variable"><Value><Calculation><![CDATA[$count + 1]]></Calculation></Value><Repetition><Calculation><![CDATA[1]]></Calculation></Repetition><Name>$count</Name></Step>"#
    let ifStep = #"<Step enable="True" id="68" name="If"><Restore state="False"/><Calculation><![CDATA[IsEmpty ( $x )]]></Calculation></Step>"#
    let endIf = #"<Step enable="True" id="70" name="End If"/>"#
    let layout = #"<Step enable="False" id="6" name="Go to Layout"><LayoutDestination value="SelectedLayout"/><Layout id="7" name="Contact List"/></Step>"#

    func testFieldVariableCalcAndLayout() {
        XCTAssertEqual(preview(setField + ifStep + setVariable + endIf + layout), """
        Set Field [ Contacts::Company … ]
        If [ IsEmpty ( $x ) … ]
            Set Variable [ $count … ]
        End If
        // Go to Layout [ "Contact List" … ]
        """)
    }

    func testCommentsAndStepsWithNothingToShow() {
        let xml = ##"<Step enable="True" id="89" name="# (comment)"><Text>PURPOSE: first line&#10;second line</Text></Step><Step enable="True" id="89" name="# (comment)"/><Step enable="True" id="1" name="Beep"/>"##
        XCTAssertEqual(preview(xml), "# PURPOSE: first line second line\n#\nBeep")
    }

    func testALongCalcIsCutAtTheFirstLineAndAt80Characters() {
        let long = String(repeating: "a", count: 100)
        let xml = #"<Step enable="True" id="103" name="Exit Script"><Calculation><![CDATA[\#(long) &"#
            + "\nsecond line]]></Calculation></Step>"
        XCTAssertEqual(preview(xml), "Exit Script [ \(String(repeating: "a", count: 80))… … ]")
    }
}

/// The title of a script: not "# (67 steps)" when the first comment is empty.
final class ScriptTitleTests: XCTestCase {
    func title(_ steps: String) -> String {
        Titles.title(for: .XMSS, data: Data("<fmxmlsnippet>\(steps)</fmxmlsnippet>".utf8), time: "T")
    }

    let empty = ##"<Step enable="True" id="89" name="# (comment)"/>"##
    func comment(_ t: String, enable: String = "True") -> String { ##"<Step enable="\##(enable)" id="89" name="# (comment)"><Text>\##(t)</Text></Step>"## }
    let errorCapture = #"<Step enable="True" id="86" name="Set Error Capture"><Set state="True"/></Step>"#
    let setField = #"<Step enable="True" id="76" name="Set Field"><Calculation><![CDATA[$name]]></Calculation><Field table="Contacts" id="2" name="Company"/></Step>"#

    func testTheFirstCommentWithTextGivesTheTitle() {
        XCTAssertEqual(title(empty + errorCapture + comment("PURPOSE: Mark the active people") + setField),
                       "# PURPOSE: Mark the active people (4 steps)")
    }

    func testABannerFrameAndAnEmptyOrDisabledCommentAreSkipped() {
        XCTAssertEqual(title(empty + comment("====") + comment("old", enable: "False") + comment("==== INITIALIZATION ====")),
                       "# INITIALIZATION (4 steps)")
    }

    func testWithNoCommentTextTheFirstStepThatDoesSomethingGivesTheTitle() {
        XCTAssertEqual(title(empty + errorCapture + setField), "Set Field [ Contacts::Company … ] (3 steps)")
        XCTAssertEqual(title(empty + errorCapture), "Set Error Capture (2 steps)")
        XCTAssertEqual(title(empty), "# (1 step)")
    }
}
