import Foundation

/// The rules to change the order of the folders. The functions are pure, so that the tests can check them.
/// The order of the folders is the order of `folders.json`. The group "No Folder" is always after the folders.
public enum FolderOrder {
    /// The type identifier of a folder drag in the list. An entry drag is plain text (the entry id), so a drop can
    /// tell the two apart: a folder drop changes the order and never moves entries.
    public static let dragType = "com.solutionscay.fm-object-clip.folder"

    /// The folders after the folder `name` moves to `index`. The index is the new position of the folder (0 is the
    /// first). An index out of range goes to the nearest end. The name match ignores the case of the letters.
    /// Returns nil if there is no folder with this name.
    public static func moved(_ folders: [String], _ name: String, to index: Int) -> [String]? {
        guard let from = folders.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        var result = folders
        let folder = result.remove(at: from)
        result.insert(folder, at: min(max(index, 0), result.count))
        return result
    }

    /// The new index of a dragged folder after a drop on a group row.
    /// - Parameters:
    ///   - folders: the folders in their order now.
    ///   - dragged: the folder that the user drags.
    ///   - target: the folder row under the pointer, or nil for the group "No Folder" (the folder goes last).
    ///   - after: true when the pointer is in the lower half of the target row (the folder goes after the target).
    /// - Returns: the index for `HistoryStore.moveFolder`, or nil when the drop changes nothing.
    public static func dropIndex(folders: [String], dragged: String, target: String?, after: Bool) -> Int? {
        guard let from = folders.firstIndex(of: dragged) else { return nil }
        var rest = folders
        rest.remove(at: from)
        let index: Int
        if let target {
            guard target != dragged, let t = rest.firstIndex(of: target) else { return nil }
            index = after ? t + 1 : t
        } else {
            index = rest.count
        }
        return index == from ? nil : index
    }

    /// True when the pointer is in the lower half of a row. The row can have empty space above it (`top`), which
    /// counts as the upper half.
    public static func isLowerHalf(y: CGFloat, top: CGFloat, height: CGFloat) -> Bool {
        y > top + height / 2
    }
}
