import AppKit

/// One FileMaker object on a pasteboard: its class, its data (UTF-8 XML), and the optional entry name and folder
/// that the tool that wrote the pasteboard gave it (see `FMPasteboard.nameType` and `FMPasteboard.folderType`).
public struct FMObject: Equatable, Sendable {
    public let cls: FMClass
    public let data: Data
    public let name: String?
    public let folder: String?

    public init(cls: FMClass, data: Data, name: String? = nil, folder: String? = nil) {
        self.cls = cls
        self.data = data
        self.name = name
        self.folder = folder
    }
}

/// Reads and writes the FileMaker classes on a pasteboard. Other contents (plain text and others) are ignored.
public enum FMPasteboard {
    /// The pasteboard class `FOPN`: the name of the entry (UTF-8 text). A tool that puts FileMaker objects on the
    /// clipboard can add it next to the FileMaker class. FileMaker Pro ignores it.
    public static let nameType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F504E")

    /// The pasteboard class `FOPF`: the folder of the entry (UTF-8 text). FileMaker Pro ignores it.
    public static let folderType = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x464F5046")

    /// The FileMaker objects that are on the pasteboard now, with the name and the folder if the pasteboard has them.
    public static func read(_ pasteboard: NSPasteboard = .general) -> [FMObject] {
        let name = readName(pasteboard)
        let folder = readFolder(pasteboard)
        return FMClass.allCases.compactMap { cls in
            guard let data = pasteboard.data(forType: cls.pasteboardType), !data.isEmpty else { return nil }
            return FMObject(cls: cls, data: data, name: name, folder: folder)
        }
    }

    /// The name on the pasteboard (class `FOPN`), or nil if there is no name or it is empty.
    public static func readName(_ pasteboard: NSPasteboard = .general) -> String? {
        guard let data = pasteboard.data(forType: nameType) else { return nil }
        return HistoryStore.cleanName(String(decoding: data, as: UTF8.self))
    }

    /// The folder on the pasteboard (class `FOPF`), or nil if there is no folder or it is empty.
    public static func readFolder(_ pasteboard: NSPasteboard = .general) -> String? {
        guard let data = pasteboard.data(forType: folderType) else { return nil }
        return HistoryStore.cleanName(String(decoding: data, as: UTF8.self))
    }

    /// Puts the data on the pasteboard with the class. Returns the new change count, or nil if the pasteboard refused the data.
    @discardableResult
    public static func write(_ data: Data, as cls: FMClass, to pasteboard: NSPasteboard = .general) -> Int? {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: cls.pasteboardType) else { return nil }
        return pasteboard.changeCount
    }
}
