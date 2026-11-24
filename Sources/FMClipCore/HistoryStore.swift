import AppKit
import CryptoKit
import Foundation

/// One entry of the history. `index.json` keeps these fields. `name` is optional: it is in the index only
/// when the user (Rename, or `fm-object-clip-cli add --name`) gave the entry a name.
public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let cls: FMClass
    public var time: String
    /// The automatic title, from the XML.
    public internal(set) var title: String
    /// The version of the title rules that made `title` (Titles.version). Nil for an entry from an earlier version.
    public var titleVersion: Int?
    public let sha256: String
    public let source: String
    public var name: String?
    /// The folder of the entry, or nil for no folder. Folders are flat.
    public var folder: String?
    /// The canonical key of the XML (see Canonical). The duplicate check uses it. Nil for an entry from an earlier
    /// version: the store makes it when it needs it.
    public var canonical: String?

    /// The title to show: the name if the entry has one, else the automatic title.
    public var displayTitle: String { name ?? title }

    enum CodingKeys: String, CodingKey {
        case id, cls = "class", time, title, titleVersion, sha256, source, name, folder, canonical
    }
}

/// The record of the last Copy Entry (app) or `restore` (CLI): the file `.last-restore.json` in the history folder.
/// While the clipboard holds this content, a capture of the same content is not a new copy: FileMaker Pro writes the
/// clipboard again when you paste. Then the entry keeps its time and its place.
public struct RestoreRecord: Codable, Equatable, Sendable {
    public let id: String
    public let cls: FMClass
    public let sha256: String
    public let canonical: String?

    enum CodingKeys: String, CodingKey {
        case id, cls = "class", sha256, canonical
    }

    /// True for the same class and the same bytes, or the same canonical XML.
    public func matches(cls: FMClass, sha256: String, canonical: String?) -> Bool {
        guard cls == self.cls else { return false }
        return sha256 == self.sha256 || (canonical != nil && canonical == self.canonical)
    }
}

/// The history on disk: one `<id>.xml` file for each entry, one `index.json` (newest entry first) and one
/// `folders.json` (the folder names, also the empty folders).
/// The files are plain, so scripts and agents can read them without the app.
///
/// More than one process can use the same history at the same time (the app and fm-object-clip-cli).
/// Each change takes an exclusive lock on the file `.lock` in the history folder, reads the latest
/// `index.json` and `folders.json`, makes the change, and writes the files atomically. Thus no change is lost.
public final class HistoryStore {
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fm-object-clip/history", isDirectory: true)
    }

    /// The size of the history. When a new entry goes over the limit, the store deletes the oldest entry.
    public static let maxEntries = 200

    public let folder: URL
    public let limit: Int
    public private(set) var entries: [HistoryEntry] = []
    /// The folders, in the order of the user (new folders at the end). Folders are flat.
    public private(set) var folders: [String] = []
    /// The messages of the repair at open, for example an `.xml` file with no index entry.
    public private(set) var repairLog: [String] = []

    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private var foldersURL: URL { folder.appendingPathComponent("folders.json") }
    private var lockURL: URL { folder.appendingPathComponent(".lock") }
    private var restoreURL: URL { folder.appendingPathComponent(".last-restore.json") }

    public init(folder: URL = HistoryStore.defaultFolder, limit: Int = HistoryStore.maxEntries) throws {
        self.folder = folder
        self.limit = limit
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try withLock { try repair() }
    }

    // MARK: - Lock and reload

    public enum StoreError: Error, LocalizedError {
        case lock(String)

        public var errorDescription: String? {
            switch self {
            case .lock(let path): return "Cannot lock the history (\(path))."
            }
        }
    }

    /// Runs body with the exclusive lock of the history, after a reload of the files on disk.
    /// Do not call a method that locks from inside body: a second lock in the same process waits for ever.
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw StoreError.lock(lockURL.path) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.lock(lockURL.path) }
        defer { flock(fd, LOCK_UN) }
        try reload()
        return try body()
    }

    /// Reads `index.json` and `folders.json` again. The app calls it when another process changed the history.
    /// The files are written atomically, so a read without the lock always gets a complete file.
    public func reload() throws {
        if let data = try? Data(contentsOf: indexURL), !data.isEmpty {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } else {
            entries = []
        }
        if let data = try? Data(contentsOf: foldersURL), !data.isEmpty {
            folders = try JSONDecoder().decode([String].self, from: data)
        } else {
            folders = []
        }
    }

    /// Removes the index entries that have no `.xml` file. Logs each `.xml` file that has no index entry, and keeps it.
    private func repair() throws {
        let fm = FileManager.default
        let before = entries.count
        entries.removeAll { !fm.fileExists(atPath: fileURL(for: $0).path) }
        if entries.count != before {
            repairLog.append("removed \(before - entries.count) index entries with no .xml file")
            try saveIndex()
        }
        let known = Set(entries.map { "\($0.id).xml" })
        let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in files.sorted() where name.hasSuffix(".xml") && !known.contains(name) {
            repairLog.append("ignored \(name): no index entry")
        }
        // A title from earlier title rules: make it again from the XML (one time for each entry).
        var retitled = false
        for k in entries.indices where (entries[k].titleVersion ?? 1) < Titles.version {
            if let data = try? Data(contentsOf: fileURL(for: entries[k])) {
                entries[k].title = Titles.title(for: entries[k].cls, data: data, time: entries[k].time)
            }
            entries[k].titleVersion = Titles.version
            retitled = true
        }
        if retitled { try saveIndex() }
        // A folder that an entry uses must be in the folder list.
        let missing = Self.unique(entries.compactMap(\.folder)).filter { f in !folders.contains(f) }
        if !missing.isEmpty {
            folders += missing
            try saveFolders()
        }
        for line in repairLog {
            FileHandle.standardError.write(Data("fm-object-clip: \(line)\n".utf8))
        }
    }

    public func fileURL(for entry: HistoryEntry) -> URL {
        folder.appendingPathComponent("\(entry.id).xml")
    }

    // MARK: - Entries

    /// Adds a capture to the history and returns its entry.
    /// If an entry has the same class and the same content, the store adds no file: it moves that entry to the top and
    /// sets its time to now. The same content is the same bytes (sha256), or the same canonical XML (see Canonical):
    /// FileMaker can put one object on the clipboard two times, compact and then pretty-printed. The entry keeps the
    /// bytes of the first capture.
    /// A new name replaces the name of that entry, and a new folder moves that entry to the folder. A capture with
    /// no name or no folder keeps the name or the folder of that entry. The store makes the folder if it does not exist.
    @discardableResult
    public func add(_ data: Data, cls: FMClass, name: String? = nil, folder: String? = nil,
                    source: String = "clipboard", now: Date = Date()) throws -> HistoryEntry {
        try withLock {
            let time = Self.isoTime(now)
            let hash = Self.sha256(data)
            let key = Canonical.key(for: data)
            let name = Self.cleanName(name)
            if source == "clipboard", name == nil, folder == nil, let restore = lastRestore(),
               restore.matches(cls: cls, sha256: hash, canonical: key),
               let i = duplicateIndex(cls: cls, sha256: hash, canonical: key) {
                // The clipboard still holds an entry that the app or the CLI put there (Copy Entry, restore).
                // FileMaker Pro writes it again, for example when you paste. The entry keeps its time and its place.
                return entries[i]
            }
            if source == "clipboard" { forgetRestore() }  // other contents are on the clipboard now
            let folder = try Self.cleanName(folder).map(makeFolderUnlocked)
            if let i = duplicateIndex(cls: cls, sha256: hash, canonical: key) {
                var entry = entries.remove(at: i)
                entry.time = time
                if let name { entry.name = name }
                if let folder { entry.folder = folder }
                entries.insert(entry, at: 0)
                try saveIndex()
                return entry
            }
            let entry = HistoryEntry(id: Self.makeID(now), cls: cls, time: time,
                                     title: Titles.title(for: cls, data: data, time: time), titleVersion: Titles.version,
                                     sha256: hash, source: source, name: name, folder: folder, canonical: key)
            try data.write(to: fileURL(for: entry), options: .atomic)
            entries.insert(entry, at: 0)
            trimToLimit()
            try saveIndex()
            return entry
        }
    }

    /// The index of the entry with the same class and the same bytes or the same canonical XML. For an entry with no
    /// canonical key (from an earlier version), the store makes the key from its file. Call it under the lock.
    private func duplicateIndex(cls: FMClass, sha256: String, canonical key: String?) -> Int? {
        if let i = entries.firstIndex(where: { $0.cls == cls && $0.sha256 == sha256 }) { return i }
        guard let key else { return nil }
        for i in entries.indices where entries[i].cls == cls {
            if entries[i].canonical == nil, let data = try? data(for: entries[i]) {
                entries[i].canonical = Canonical.key(for: data)  // saved with the next write of the index
            }
            if entries[i].canonical == key { return i }
        }
        return nil
    }

    /// The canonical key of an entry: from the index, else from its file.
    public func canonicalKey(for entry: HistoryEntry) -> String? {
        entry.canonical ?? (try? data(for: entry)).flatMap(Canonical.key)
    }

    /// Puts back an entry that was deleted (Undo), with its id, time, name, folder and bytes.
    /// It goes to its place by time. The store makes its folder again if necessary. Nothing happens if the id exists.
    @discardableResult
    public func insert(_ entry: HistoryEntry, data: Data) throws -> HistoryEntry {
        try insert([(entry, data)]).first ?? entry
    }

    /// Puts back many deleted entries in one change (Undo of a bulk delete).
    @discardableResult
    public func insert(_ items: [(HistoryEntry, Data)]) throws -> [HistoryEntry] {
        try withLock {
            var result: [HistoryEntry] = []
            var foldersChanged = false
            for (entry, data) in items {
                if let existing = entries.first(where: { $0.id == entry.id }) {
                    result.append(existing)
                    continue
                }
                if let f = entry.folder, existingFolder(f) == nil {
                    folders.append(f)
                    foldersChanged = true
                }
                try data.write(to: fileURL(for: entry), options: .atomic)
                let i = entries.firstIndex { $0.time < entry.time } ?? entries.count
                entries.insert(entry, at: i)
                result.append(entry)
            }
            if foldersChanged { try saveFolders() }
            try saveIndex()
            return result
        }
    }

    /// The size limit counts all the entries, but deletes only the oldest entries that are in no folder.
    private func trimToLimit() {
        while entries.count > limit, let i = entries.lastIndex(where: { $0.folder == nil }) {
            let old = entries.remove(at: i)
            try? FileManager.default.removeItem(at: fileURL(for: old))
        }
    }

    /// Gives the entry a name. An empty name removes the name, and the entry shows its automatic title again.
    /// The XML file does not change.
    @discardableResult
    public func rename(id: String, to name: String?) throws -> HistoryEntry? {
        try withLock {
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
            entries[i].name = Self.cleanName(name)
            try saveIndex()
            return entries[i]
        }
    }

    /// Moves an entry to a folder, or to no folder (nil or an empty name). The store makes the folder if it does not exist.
    @discardableResult
    public func move(id: String, to folder: String?) throws -> HistoryEntry? {
        try withLock {
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
            entries[i].folder = try Self.cleanName(folder).map(makeFolderUnlocked)
            let entry = entries[i]
            trimToLimit()
            try saveIndex()
            return entry
        }
    }

    /// Moves many entries to a folder, or to no folder (nil), in one change. Returns the moved entries.
    @discardableResult
    public func move(ids: [String], to folder: String?) throws -> [HistoryEntry] {
        try withLock {
            let target = try Self.cleanName(folder).map(makeFolderUnlocked)
            let wanted = Set(ids)
            var moved: [HistoryEntry] = []
            for i in entries.indices where wanted.contains(entries[i].id) {
                entries[i].folder = target
                moved.append(entries[i])
            }
            guard !moved.isEmpty else { return [] }
            trimToLimit()
            try saveIndex()
            return moved
        }
    }

    /// Deletes an entry and its XML file. Returns the deleted entry, or nil if the id does not exist.
    @discardableResult
    public func delete(id: String) throws -> HistoryEntry? {
        try delete(ids: [id]).first
    }

    /// Deletes the entries with these ids, in one change. Returns the deleted entries (ids that do not exist are skipped).
    @discardableResult
    public func delete(ids: [String]) throws -> [HistoryEntry] {
        try withLock {
            let wanted = Set(ids)
            let gone = entries.filter { wanted.contains($0.id) }
            guard !gone.isEmpty else { return [] }
            entries.removeAll { wanted.contains($0.id) }
            for entry in gone { try? FileManager.default.removeItem(at: fileURL(for: entry)) }
            try saveIndex()
            return gone
        }
    }

    // MARK: - Folders

    public enum FolderError: Error, LocalizedError, Equatable {
        case emptyName
        case exists(String)
        case notFound(String)

        public var errorDescription: String? {
            switch self {
            case .emptyName: return "The folder name is empty."
            case .exists(let name): return "A folder with the name \"\(name)\" exists."
            case .notFound(let name): return "There is no folder with the name \"\(name)\"."
            }
        }
    }

    /// The folder with this name (the case of the letters does not matter). Nil if it does not exist.
    public func existingFolder(_ name: String) -> String? {
        folders.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Makes a folder and returns its name. If a folder with the same name exists, returns that folder.
    @discardableResult
    public func makeFolder(_ name: String) throws -> String {
        try withLock { try makeFolderUnlocked(name) }
    }

    private func makeFolderUnlocked(_ name: String) throws -> String {
        guard let clean = Self.cleanName(name) else { throw FolderError.emptyName }
        if let existing = existingFolder(clean) { return existing }
        folders.append(clean)
        try saveFolders()
        return clean
    }

    /// Renames a folder and returns the new name. The entries of the folder go with it.
    @discardableResult
    public func renameFolder(_ old: String, to new: String) throws -> String {
        try withLock {
            guard let current = existingFolder(old) else { throw FolderError.notFound(old) }
            guard let clean = Self.cleanName(new) else { throw FolderError.emptyName }
            if let other = existingFolder(clean), other != current { throw FolderError.exists(other) }
            folders[folders.firstIndex(of: current)!] = clean
            for i in entries.indices where entries[i].folder == current { entries[i].folder = clean }
            try saveFolders()
            try saveIndex()
            return clean
        }
    }

    /// Deletes a folder and returns the number of its entries. Its entries stay in the history, in no folder.
    @discardableResult
    public func deleteFolder(_ name: String) throws -> Int {
        try withLock {
            guard let current = existingFolder(name) else { throw FolderError.notFound(name) }
            folders.removeAll { $0 == current }
            var moved = 0
            for i in entries.indices where entries[i].folder == current {
                entries[i].folder = nil
                moved += 1
            }
            trimToLimit()
            try saveFolders()
            try saveIndex()
            return moved
        }
    }

    /// The number of entries in the folder.
    public func count(in folder: String) -> Int {
        entries.filter { $0.folder == folder }.count
    }

    // MARK: - Read

    public func entry(id: String) -> HistoryEntry? {
        entries.first { $0.id == id }
    }

    public func data(for entry: HistoryEntry) throws -> Data {
        try Data(contentsOf: fileURL(for: entry))
    }

    /// Which entries a query keeps by folder.
    public enum FolderScope: Equatable {
        case any
        case folder(String)
        case none
    }

    /// The entries that match the folder, the class and the search text (name, automatic title or XML, any case).
    public func query(scope: FolderScope = .any, cls: FMClass? = nil, search: String? = nil, limit: Int? = nil) -> [HistoryEntry] {
        let text = (search ?? "").trimmingCharacters(in: .whitespaces)
        var result = entries.filter { e in
            switch scope {
            case .any: break
            case .folder(let f): if e.folder?.caseInsensitiveCompare(f) != .orderedSame { return false }
            case .none: if e.folder != nil { return false }
            }
            if let cls, e.cls != cls { return false }
            if text.isEmpty { return true }
            if e.displayTitle.localizedCaseInsensitiveContains(text) || e.title.localizedCaseInsensitiveContains(text) {
                return true
            }
            let xml = (try? data(for: e)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            return xml.localizedCaseInsensitiveContains(text)
        }
        if let limit, limit >= 0, result.count > limit { result = Array(result.prefix(limit)) }
        return result
    }

    /// Puts the entry on the pasteboard with its class, with the bytes as captured (never the formatted XML).
    /// Returns the new change count, or nil if the pasteboard refused the data.
    @discardableResult
    /// The store first writes the record `.last-restore.json` in the history folder (see `RestoreRecord`), so that the
    /// watcher of the app, or of another process, does not move the entry to the top when it sees the copy.
    public func copy(_ entry: HistoryEntry, to pasteboard: NSPasteboard = .general) throws -> Int? {
        let data = try data(for: entry)
        let record = RestoreRecord(id: entry.id, cls: entry.cls, sha256: entry.sha256,
                                   canonical: entry.canonical ?? Canonical.key(for: data))
        try? JSONEncoder().encode(record).write(to: restoreURL, options: .atomic)
        return FMPasteboard.write(data, as: entry.cls, to: pasteboard)
    }

    /// The entry that the app or the CLI put on the clipboard last, while the clipboard has no other contents.
    public func lastRestore() -> RestoreRecord? {
        guard let data = try? Data(contentsOf: restoreURL) else { return nil }
        return try? JSONDecoder().decode(RestoreRecord.self, from: data)
    }

    /// Removes the restore record. Call it when the clipboard gets other contents (also contents with no FileMaker class).
    public func forgetRestore() {
        guard FileManager.default.fileExists(atPath: restoreURL.path) else { return }
        try? FileManager.default.removeItem(at: restoreURL)
    }

    // MARK: - Helpers

    /// The name without space at the two ends and on one line. Nil if nothing is left.
    public static func cleanName(_ name: String?) -> String? {
        let clean = (name ?? "").components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : clean
    }

    /// Writes a temporary file, then moves it into place (Data.WritingOptions.atomic).
    func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    func saveFolders() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(folders).write(to: foldersURL, options: .atomic)
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isoTime(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func makeID(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date) + "-" + UUID().uuidString.prefix(8).lowercased()
    }
}

/// Calls onChange (on the main queue) when a file in the history folder changes, for example when another
/// process writes `index.json`. Changes in a short time give one call.
public final class HistoryFolderWatcher {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?

    public init?(folder: URL, delay: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
