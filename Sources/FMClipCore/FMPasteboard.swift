import AppKit

/// One FileMaker object on a pasteboard: its class and its data (UTF-8 XML).
public struct FMObject: Equatable, Sendable {
    public let cls: FMClass
    public let data: Data

    public init(cls: FMClass, data: Data) {
        self.cls = cls
        self.data = data
    }
}

/// Reads and writes the FileMaker classes on a pasteboard. Other contents (plain text and others) are ignored.
public enum FMPasteboard {
    /// The FileMaker objects that are on the pasteboard now.
    public static func read(_ pasteboard: NSPasteboard = .general) -> [FMObject] {
        FMClass.allCases.compactMap { cls in
            guard let data = pasteboard.data(forType: cls.pasteboardType), !data.isEmpty else { return nil }
            return FMObject(cls: cls, data: data)
        }
    }

    /// Puts the data on the pasteboard with the class. Returns the new change count, or nil if the pasteboard refused the data.
    @discardableResult
    public static func write(_ data: Data, as cls: FMClass, to pasteboard: NSPasteboard = .general) -> Int? {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: cls.pasteboardType) else { return nil }
        return pasteboard.changeCount
    }
}
