import Foundation

/// One row of the history list: a folder row (with a disclosure triangle) or an entry row.
public struct TreeRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A folder. `count` is the number of entries that the row stands for: all its entries, or only the matches
        /// while a filter or a search is active.
        case folder(name: String, count: Int, expanded: Bool)
        /// The group "No Folder" for the entries that are in no folder. It comes after the folders.
        case noFolder(count: Int, expanded: Bool)
        /// An entry. `indented` is true for an entry under a group row (a folder or "No Folder").
        case entry(HistoryEntry, indented: Bool)
    }

    public let kind: Kind

    public var id: String {
        switch kind {
        case .folder(let name, _, _): return "folder:" + name
        case .noFolder: return "no-folder"
        case .entry(let e, _): return e.id
        }
    }

    public var entry: HistoryEntry? {
        if case .entry(let e, _) = kind { return e }
        return nil
    }
}

/// Makes the rows of the history list: the folders first (in the order of the folder list), each with its entries
/// under it when it is expanded (in the order of `ordered`), then the group "No Folder" with the entries in no folder. Each entry is under a group row.
public enum HistoryTree {
    /// The order of the entries in a folder. When each entry has a name, the order is by name, in the natural order
    /// of the Finder ("2" before "10"), so that a numbered set ("01 …" to "17 …") stays in order. Else the order is
    /// newest first. Entries with the same name stay newest first.
    public static func ordered(_ inFolder: [HistoryEntry]) -> [HistoryEntry] {
        guard !inFolder.isEmpty, inFolder.allSatisfy({ $0.name != nil }) else { return inFolder }
        return inFolder.enumerated().sorted { a, b in
            let order = a.element.name!.localizedStandardCompare(b.element.name!)
            return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
        }.map(\.element)
    }


    /// - Parameters:
    ///   - entries: all the entries, newest first.
    ///   - folders: all the folders, also the empty folders.
    ///   - expanded: the folders that the user expanded.
    ///   - noFolderExpanded: true when the group "No Folder" is expanded.
    ///   - active: true while a type filter or a search is active. Then only the folders with a match show, expanded.
    ///   - matches: true for an entry that matches the type filter and the search.
    public static func rows(entries: [HistoryEntry], folders: [String], expanded: Set<String>,
                            noFolderExpanded: Bool = true, active: Bool,
                            matches: (HistoryEntry) -> Bool) -> [TreeRow] {
        var rows: [TreeRow] = []
        for folder in folders {
            let inFolder = ordered(entries.filter { $0.folder == folder })
            let shown = active ? inFolder.filter(matches) : inFolder
            if active && shown.isEmpty { continue }
            let open = active || expanded.contains(folder)
            rows.append(TreeRow(kind: .folder(name: folder, count: shown.count, expanded: open)))
            if open { rows += shown.map { TreeRow(kind: .entry($0, indented: true)) } }
        }
        let known = Set(folders)
        let loose = entries.filter { $0.folder == nil || !known.contains($0.folder!) }
        let shownLoose = active ? loose.filter(matches) : loose
        if !shownLoose.isEmpty {
            let open = active || noFolderExpanded
            rows.append(TreeRow(kind: .noFolder(count: shownLoose.count, expanded: open)))
            if open { rows += shownLoose.map { TreeRow(kind: .entry($0, indented: true)) } }
        }
        return rows
    }
}
