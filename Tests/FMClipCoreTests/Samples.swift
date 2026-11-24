import Foundation
@testable import FMClipCore

/// Small generic FileMaker clipboard XML for the tests: a "Contacts" file with First Name and Last Name.
/// The script steps and the layout objects are pretty-printed with tabs and a declaration, as FileMaker Pro can put
/// them on the clipboard. The tables and the fields are compact, on one line.
enum Samples {
    static func data(for cls: FMClass) -> Data {
        switch cls {
        case .XMSS: return Data(steps.utf8)
        case .XMTB: return Data(tables.utf8)
        case .XMFD: return Data(fields.utf8)
        case .XML2: return Data(layout.utf8)
        }
    }

    /// 11 steps. Title: "# PURPOSE: count the contacts with no e-mail address (11 steps)".
    static let steps = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <fmxmlsnippet type="FMObjectList">
    	<Step enable="True" id="89" name="# (comment)">
    		<Text>PURPOSE: count the contacts with no e-mail address</Text>
    	</Step>
    	<Step enable="True" id="86" name="Set Error Capture">
    		<Set state="True"/>
    	</Step>
    	<Step enable="True" id="141" name="Set Variable">
    		<Value>
    			<Calculation><![CDATA[0]]></Calculation>
    		</Value>
    		<Repetition>
    			<Calculation><![CDATA[1]]></Calculation>
    		</Repetition>
    		<Name>$count</Name>
    	</Step>
    	<Step enable="True" id="16" name="Go to Record/Request/Page">
    		<NoInteract state="True"/>
    		<RowPageLocation value="First"/>
    	</Step>
    	<Step enable="True" id="71" name="Loop"/>
    	<Step enable="True" id="68" name="If">
    		<Calculation><![CDATA[IsEmpty ( Contacts::Email )]]></Calculation>
    	</Step>
    	<Step enable="True" id="141" name="Set Variable">
    		<Value>
    			<Calculation><![CDATA[$count + 1]]></Calculation>
    		</Value>
    		<Repetition>
    			<Calculation><![CDATA[1]]></Calculation>
    		</Repetition>
    		<Name>$count</Name>
    	</Step>
    	<Step enable="True" id="70" name="End If"/>
    	<Step enable="True" id="16" name="Go to Record/Request/Page">
    		<NoInteract state="True"/>
    		<Exit state="True"/>
    		<RowPageLocation value="Next"/>
    	</Step>
    	<Step enable="True" id="73" name="End Loop"/>
    	<Step enable="True" id="87" name="Show Custom Dialog">
    		<Title>
    			<Calculation><![CDATA["Contacts"]]></Calculation>
    		</Title>
    		<Message>
    			<Calculation><![CDATA[$count & " contacts with no e-mail address"]]></Calculation>
    		</Message>
    	</Step>
    </fmxmlsnippet>
    """#

    /// 2 tables. Title: "Contacts, Email Addresses".
    static let tables = #"<fmxmlsnippet type="FMObjectList"><BaseTable name="Contacts"><Field id="1" dataType="Text" fieldType="Normal" name="First Name"><Validation message="False" maxLength="False" valuelist="False" calculation="False" alwaysValidateCalculation="False" type="OnlyDuringDataEntry"><NotEmpty value="True"></NotEmpty><Unique value="False"></Unique></Validation></Field><Field id="2" dataType="Text" fieldType="Normal" name="Last Name"></Field></BaseTable><BaseTable name="Email Addresses"><Field id="1" dataType="Text" fieldType="Normal" name="Address"></Field><Field id="2" dataType="Number" fieldType="Normal" name="Contact ID"></Field></BaseTable></fmxmlsnippet>"#

    /// 4 fields. Title: "First Name, Last Name, Created, … (4 fields)".
    static let fields = #"<fmxmlsnippet type="FMObjectList"><Field id="1" dataType="Text" fieldType="Normal" name="First Name"><Comment>Given name</Comment><AutoEnter allowEditing="True" constant="False" furigana="False" lookup="False" calculation="False"><ConstantData></ConstantData></AutoEnter><Validation message="False" maxLength="False" valuelist="False" calculation="False" alwaysValidateCalculation="False" type="OnlyDuringDataEntry"><NotEmpty value="True"></NotEmpty><Unique value="False"></Unique></Validation></Field><Field id="2" dataType="Text" fieldType="Normal" name="Last Name"><AutoEnter allowEditing="True" constant="False" furigana="False" lookup="False" calculation="False"><ConstantData></ConstantData></AutoEnter></Field><Field id="3" dataType="TimeStamp" fieldType="Normal" name="Created"><AutoEnter allowEditing="False" constant="False" furigana="False" lookup="False" calculation="False" value="CreationTimeStamp"><ConstantData></ConstantData></AutoEnter></Field><Field id="4" dataType="Text" fieldType="Calculated" name="Full Name"><Calculation><![CDATA[First Name & " " & Last Name]]></Calculation></Field></fmxmlsnippet>"#

    /// 4 layout objects: 2 labels and 2 fields. Title: "4 layout objects".
    static let layout = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <fmxmlsnippet type="LayoutObjectList">
    	<Layout enclosingRectTop="10" enclosingRectLeft="10" enclosingRectBottom="60" enclosingRectRight="330">
    		<Object type="Text" key="1" LabelKey="0" flags="0" rotation="0">
    			<Bounds top="12" left="10" bottom="28" right="100"/>
    			<TextObj flags="0">
    				<CharacterStyleVector>
    					<Style>
    						<Data>First Name</Data>
    					</Style>
    				</CharacterStyleVector>
    			</TextObj>
    		</Object>
    		<Object type="Field" key="2" LabelKey="1" flags="0" rotation="0">
    			<Bounds top="10" left="110" bottom="30" right="330"/>
    			<FieldObj numOfReps="1" flags="0" inputMode="0" keyboardType="1" displayType="0" quickFind="1" pictFormat="5">
    				<Name>Contacts::First Name</Name>
    			</FieldObj>
    		</Object>
    		<Object type="Text" key="3" LabelKey="0" flags="0" rotation="0">
    			<Bounds top="42" left="10" bottom="58" right="100"/>
    			<TextObj flags="0">
    				<CharacterStyleVector>
    					<Style>
    						<Data>Last Name</Data>
    					</Style>
    				</CharacterStyleVector>
    			</TextObj>
    		</Object>
    		<Object type="Field" key="4" LabelKey="3" flags="0" rotation="0">
    			<Bounds top="40" left="110" bottom="60" right="330"/>
    			<FieldObj numOfReps="1" flags="0" inputMode="0" keyboardType="1" displayType="0" quickFind="1" pictFormat="5">
    				<Name>Contacts::Last Name</Name>
    			</FieldObj>
    		</Object>
    	</Layout>
    </fmxmlsnippet>
    """#
}
