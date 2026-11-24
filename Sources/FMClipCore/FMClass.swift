import AppKit

/// The FileMaker Pro pasteboard classes that the app keeps.
public enum FMClass: String, CaseIterable, Codable, Sendable {
    case XMSS  // script steps
    case XMTB  // tables
    case XMFD  // fields
    case XML2  // layout objects

    /// "CorePasteboardFlavorType 0x" and the hex of the 4 ASCII letters, the type FileMaker Pro uses on macOS.
    public var pasteboardType: NSPasteboard.PasteboardType {
        let hex = rawValue.utf8.map { String(format: "%02X", $0) }.joined()
        return NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x" + hex)
    }

    /// The name of the class in the window.
    public var label: String {
        switch self {
        case .XMSS: return "Scripts"
        case .XMTB: return "Tables"
        case .XMFD: return "Fields"
        case .XML2: return "Layout"
        }
    }
}
