import Foundation

/// A backup of the full history in one JSON file: all the entries with their XML bytes, the folders in their order,
/// and the settings. The file is UTF-8 JSON, pretty-printed, with sorted keys:
///
///     { "format": "fm-object-clip-backup", "version": 1, "created": "<ISO time>",
///       "folders": [...], "settings": { ... } or null,
///       "entries": [ { <the fields of index.json>, "data": "<base64 of the XML bytes>" }, ... ] }
///
/// The entries are in the order of the index (newest first). The XML is base64, so the bytes stay exact and the
/// sha256 of each entry stays correct.
public struct Backup {
    public static let format = "fm-object-clip-backup"
    /// The version of the file format that this code writes and reads. A file with a higher version is refused.
    public static let version = 1

    /// One entry of the backup: the entry as the index has it, and its XML bytes.
    public struct Item {
        public var entry: HistoryEntry
        public var data: Data

        public init(entry: HistoryEntry, data: Data) {
            self.entry = entry
            self.data = data
        }
    }

    public var created: String
    public var folders: [String]
    /// The object of `settings.json`, or nil if the history has no settings file. The backup does not look at its keys.
    public var settings: [String: Any]?
    public var items: [Item]

    public init(created: String, folders: [String], settings: [String: Any]?, items: [Item]) {
        self.created = created
        self.folders = folders
        self.settings = settings
        self.items = items
    }

    /// The default file name: `fm-object-clip-backup-YYYY-MM-DD.json` (the local date).
    public static func defaultFileName(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "fm-object-clip-backup-\(f.string(from: date)).json"
    }

    // MARK: - Errors

    public enum BackupError: Error, LocalizedError, Equatable {
        case notBackup(String)
        case newerVersion(Int)
        case unknownVersion(Int)
        case badEntry(Int, String)
        case badData(String)
        case checksum(String)
        case duplicateID(String)
        /// Two ids that differ only in case (or Unicode form): on a case-insensitive volume they are one file.
        case caseDuplicateID(String, String)

        public var errorDescription: String? {
            switch self {
            case .notBackup(let why):
                return "The file is not an fm-object-clip backup (\(why))."
            case .newerVersion(let v):
                return "The backup has version \(v). This version of fm-object-clip reads only version \(Backup.version). Update fm-object-clip."
            case .unknownVersion(let v):
                return "The backup has version \(v). fm-object-clip reads only version \(Backup.version)."
            case .badEntry(let i, let why):
                return "Entry \(i + 1) of the backup is not correct: \(why)."
            case .badData(let id):
                return "The XML data of the entry \(id) in the backup is not correct base64."
            case .checksum(let id):
                return "The XML data of the entry \(id) in the backup does not agree with its sha256. The file is damaged."
            case .duplicateID(let id):
                return "The backup has the entry id \(id) two times."
            case .caseDuplicateID(let a, let b):
                return "The backup has the entry ids \(a) and \(b). They differ only in case, so on macOS they name the same file. The file is damaged."
            }
        }
    }

    // MARK: - Write

    /// The bytes of the backup file.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        var list: [[String: Any]] = []
        for item in items {
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(item.entry))
            guard var dict = json as? [String: Any] else { continue }
            dict["data"] = item.data.base64EncodedString()
            list.append(dict)
        }
        let root: [String: Any] = [
            "format": Self.format,
            "version": Self.version,
            "created": created,
            "folders": folders,
            "settings": settings as Any? ?? NSNull(),
            "entries": list,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Writes the backup file atomically.
    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    // MARK: - Read

    private struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    /// Reads and validates a backup file. A bad file throws a BackupError.
    public static func read(from url: URL) throws -> Backup {
        try decode(try Data(contentsOf: url))
    }

    /// Validates and decodes the bytes of a backup file. The format must agree, the version must be 1, each entry
    /// must decode, and the bytes of each entry must agree with its sha256. The canonical key of each entry comes
    /// from its bytes, not from the file.
    public static func decode(_ data: Data) throws -> Backup {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw BackupError.notBackup("no JSON object")
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == format else {
            throw BackupError.notBackup("the format is not \(format)")
        }
        guard let version = header.version else { throw BackupError.notBackup("no version number") }
        if version > Self.version { throw BackupError.newerVersion(version) }
        if version != Self.version { throw BackupError.unknownVersion(version) }

        guard let folders = root["folders"] as? [String] else { throw BackupError.notBackup("no folder list") }
        var settings: [String: Any]?
        switch root["settings"] {
        case nil, is NSNull: settings = nil
        case let dict as [String: Any]: settings = dict
        default: throw BackupError.notBackup("the settings are not a JSON object")
        }
        guard let list = root["entries"] as? [[String: Any]] else { throw BackupError.notBackup("no entry list") }

        var items: [Item] = []
        var ids = Set<String>()
        var fileKeys: [String: String] = [:]  // file key → the first id with it
        for (i, raw) in list.enumerated() {
            var dict = raw
            guard let base64 = dict.removeValue(forKey: "data") as? String else { throw BackupError.badEntry(i, "no data") }
            var entry: HistoryEntry
            do {
                entry = try JSONDecoder().decode(HistoryEntry.self, from: try JSONSerialization.data(withJSONObject: dict))
            } catch {
                throw BackupError.badEntry(i, "a field is missing or has the wrong type")
            }
            guard isSafeID(entry.id) else { throw BackupError.badEntry(i, "the id \(entry.id) is not a safe file name") }
            guard ids.insert(entry.id).inserted else { throw BackupError.duplicateID(entry.id) }
            let key = HistoryStore.fileKey(entry.id)
            if let other = fileKeys[key] { throw BackupError.caseDuplicateID(other, entry.id) }
            fileKeys[key] = entry.id
            guard let bytes = Data(base64Encoded: base64) else { throw BackupError.badData(entry.id) }
            guard HistoryStore.sha256(bytes) == entry.sha256 else { throw BackupError.checksum(entry.id) }
            // The duplicate check uses the canonical key: make it from the checked bytes, do not trust the file.
            entry.canonical = Canonical.key(for: bytes)
            items.append(Item(entry: entry, data: bytes))
        }
        return Backup(created: root["created"] as? String ?? "", folders: folders, settings: settings, items: items)
    }

    /// The id becomes a file name (`<id>.xml`): it must not go out of the history folder or make a hidden file.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && !id.contains("/") && !id.contains(":") && !id.contains("\0") && id.count <= 200
    }
}

// MARK: - The store

extension HistoryStore {
    /// The counts of a Merge.
    public struct MergeResult: Equatable {
        public var added = 0
        public var skippedDuplicates = 0
        public var foldersAdded = 0
    }

    /// The result of a Replace.
    public struct ReplaceResult: Equatable {
        public var entries = 0
        public var folders = 0
        /// The backup of the history before the Replace.
        public var safetyBackup: URL
    }

    /// The folder of the safety backups: `backups` next to the history folder.
    public var backupsFolder: URL {
        folder.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// Makes a backup of the full history, under the lock, so that the backup is a consistent snapshot.
    public func makeBackup(now: Date = Date()) throws -> Backup {
        try withLock { try makeBackupUnlocked(now: now) }
    }

    /// Makes a backup and writes it to the file. Returns the backup.
    @discardableResult
    public func writeBackup(to url: URL, now: Date = Date()) throws -> Backup {
        let backup = try makeBackup(now: now)
        try backup.write(to: url)
        return backup
    }

    private func makeBackupUnlocked(now: Date) throws -> Backup {
        let items = try entries.map { Backup.Item(entry: $0, data: try data(for: $0)) }
        var settings: [String: Any]?
        // The settings file of issue #3 (SettingsStore). Backup treats it as an opaque JSON object.
        if let data = try? Data(contentsOf: SettingsStore.url(in: folder)) {
            settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return Backup(created: Self.isoTime(now), folders: folders, settings: settings, items: items)
    }

    /// Adds the entries of the backup that are not in the history. An entry with the same class and the same content
    /// (the same rule as a capture) is skipped. A new entry keeps its id, time, name, folder and bytes; if its id is
    /// in use, it gets a new id. The missing folders go after the current folders, in the order of the backup.
    /// The settings do not change. The size limit deletes nothing here.
    @discardableResult
    public func merge(_ backup: Backup) throws -> MergeResult {
        try withLock {
            var result = MergeResult()
            var written: [URL] = []
            let oldFolders = folders
            do {
                func folderName(_ name: String?) -> String? {
                    guard let clean = Self.cleanName(name) else { return nil }
                    if let existing = existingFolder(clean) { return existing }
                    folders.append(clean)
                    result.foldersAdded += 1
                    return clean
                }
                for f in backup.folders { _ = folderName(f) }
                // The ids in use, by file key: the index and the .xml files, without case (see `fileKey`).
                var taken = Set(entries.map { Self.fileKey($0.id) })
                for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".xml") {
                    taken.insert(Self.fileKey(String(name.dropLast(4))))
                }
                for item in backup.items {
                    var entry = item.entry
                    let key = Canonical.key(for: item.data)
                    if duplicateIndex(cls: entry.cls, sha256: entry.sha256, canonical: key) != nil {
                        result.skippedDuplicates += 1
                        continue
                    }
                    entry.canonical = key
                    entry.folder = folderName(entry.folder)
                    if taken.contains(Self.fileKey(entry.id)) { entry = entry.withID(freeID(near: entry.time, taken: taken)) }
                    taken.insert(Self.fileKey(entry.id))
                    let url = fileURL(for: entry)
                    try item.data.write(to: url, options: .atomic)
                    written.append(url)
                    let i = entries.firstIndex { $0.time < entry.time } ?? entries.count
                    entries.insert(entry, at: i)
                    result.added += 1
                }
                if result.foldersAdded > 0 { try saveFolders() }
                if result.added > 0 { try saveIndex() }
            } catch {
                // Nothing changes: remove the new files and read the old index and folders again.
                for url in written { try? FileManager.default.removeItem(at: url) }
                folders = oldFolders
                if result.foldersAdded > 0 { try? saveFolders() }
                try? reload()
                throw error
            }
            return result
        }
    }

    /// Replaces the full history and the settings with the backup.
    ///
    /// First it writes a safety backup of the current history to `backupsFolder`. Then it writes the XML files, the
    /// settings, the folders, and last the index. The index is the commit point: until it is written, the old index
    /// is the history. If a step before the index fails, the store puts back the old files and removes the new files,
    /// and the history stays as it was. After the index, it removes the XML files that the new index does not use.
    /// It does not swap the full history folder: the app watches that folder, and the lock file is in it.
    @discardableResult
    public func replace(with backup: Backup, now: Date = Date()) throws -> ReplaceResult {
        try withLock {
            let fm = FileManager.default
            let safety = try writeSafetyBackup(now: now)

            var newFolders = Self.unique(backup.folders.compactMap { Self.cleanName($0) })
            for f in backup.items.compactMap(\.entry.folder) where !newFolders.contains(f) { newFolders.append(f) }
            let newEntries = backup.items.map(\.entry)
            let oldEntries = entries
            let oldFolders = folders

            // The old bytes, to put back if a step fails.
            var restoreFiles: [(URL, Data?)] = []
            func remember(_ url: URL) {
                restoreFiles.append((url, try? Data(contentsOf: url)))
            }
            do {
                for item in backup.items {
                    let url = fileURL(for: item.entry)
                    if let old = try? Data(contentsOf: url), old == item.data { continue }
                    remember(url)
                    try item.data.write(to: url, options: .atomic)
                }
                let settingsURL = SettingsStore.url(in: folder)
                remember(settingsURL)
                if let settings = backup.settings {
                    let data = try JSONSerialization.data(withJSONObject: settings,
                                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    try data.write(to: settingsURL, options: .atomic)
                } else if fm.fileExists(atPath: settingsURL.path) {
                    try fm.removeItem(at: settingsURL)
                }
                folders = newFolders
                try saveFolders()
                entries = newEntries
                try saveIndex()  // the commit point
            } catch {
                for (url, data) in restoreFiles.reversed() {
                    if let data { try? data.write(to: url, options: .atomic) } else { try? fm.removeItem(at: url) }
                }
                entries = oldEntries
                folders = oldFolders
                try? saveFolders()
                throw error
            }
            // Remove the XML files that the new index does not use. Compare without case: on a case-insensitive volume
            // `Original.xml` and `original.xml` are one file, and removing it would remove the new entry's XML.
            let keepIDs = Set(newEntries.map(\.id))
            let keepByKey = Dictionary(newEntries.map { (Self.fileKey($0.id), $0) }, uniquingKeysWith: { a, _ in a })
            for old in oldEntries where !keepIDs.contains(old.id) {
                let url = fileURL(for: old)
                // Same key: remove the old file only when it is another file (a case-sensitive volume).
                if let kept = keepByKey[Self.fileKey(old.id)], Self.isSameFile(url, fileURL(for: kept)) { continue }
                try? fm.removeItem(at: url)
            }
            matchFileNameSpelling(of: newEntries)
            forgetRestore()
            try? writeGeneration()  // after the commit point: a failure here must not report a failed Replace
            try reload()
            return ReplaceResult(entries: entries.count, folders: folders.count, safetyBackup: safety)
        }
    }

    /// Writes a backup of the current history to `backupsFolder/fm-object-clip-before-restore-<time>.json`.
    /// Call it under the lock.
    private func writeSafetyBackup(now: Date) throws -> URL {
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: now)
        var url = backupsFolder.appendingPathComponent("fm-object-clip-before-restore-\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupsFolder.appendingPathComponent("fm-object-clip-before-restore-\(stamp)-\(n).json")
            n += 1
        }
        try makeBackupUnlocked(now: now).write(to: url)
        return url
    }

    /// True if no entry has the id and no file has its name.
    /// The key of an id as a file name: without case and in one Unicode form, as a case-insensitive volume
    /// (the default on macOS) compares names. Two ids with the same key can be one `.xml` file.
    static func fileKey(_ id: String) -> String {
        id.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// On a case-insensitive volume, writing `original.xml` over `Original.xml` keeps the old spelling of the name.
    /// Give each file the spelling of its entry id (a case-only rename), so that the next open finds no file
    /// "with no index entry". Call it under the lock, after the commit point. A failure leaves the file readable.
    private func matchFileNameSpelling(of entries: [HistoryEntry]) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".xml") }
        let byKey = Dictionary(names.map { (Self.fileKey(String($0.dropLast(4))), $0) }, uniquingKeysWith: { a, _ in a })
        for entry in entries {
            let expected = "\(entry.id).xml"
            guard let actual = byKey[Self.fileKey(entry.id)], actual != expected else { continue }
            let from = folder.appendingPathComponent(actual), to = folder.appendingPathComponent(expected)
            guard Self.isSameFile(from, to) else { continue }  // two files on a case-sensitive volume: leave them
            _ = from.withUnsafeFileSystemRepresentation { f in
                to.withUnsafeFileSystemRepresentation { t in
                    guard let f, let t else { return Int32(-1) }
                    return Darwin.rename(f, t)
                }
            }
        }
    }

    /// True when the two URLs name one file on disk (the same file number on the same volume).
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let x = try? fm.attributesOfItem(atPath: a.path), let y = try? fm.attributesOfItem(atPath: b.path),
              let fx = x[.systemFileNumber] as? UInt64, let fy = y[.systemFileNumber] as? UInt64 else { return false }
        return fx == fy && (x[.systemNumber] as? Int) == (y[.systemNumber] as? Int)
    }

    /// A new id whose file key is not taken. It starts with the time of the entry, so the ids stay in time order.
    private func freeID(near time: String, taken: Set<String>) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: time) ?? Date()
        var id = Self.makeID(date)
        while taken.contains(Self.fileKey(id))
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(id).xml").path) {
            id = Self.makeID(date)
        }
        return id
    }

    // MARK: - Generation

    /// The file with the generation of the history. A Replace writes a new value; other changes keep it.
    var generationURL: URL { folder.appendingPathComponent(".generation") }

    /// The generation of the history: a new UUID after each Replace, or nil if the history was never replaced.
    /// The app compares it after a change on disk: a new value means that its Undo actions and caches are old.
    public var generation: String? {
        guard let data = try? Data(contentsOf: generationURL),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Writes a new generation. Call it under the lock.
    private func writeGeneration() throws {
        try Data((UUID().uuidString + "\n").utf8).write(to: generationURL, options: .atomic)
    }
}

extension HistoryEntry {
    /// The same entry with another id.
    func withID(_ id: String) -> HistoryEntry {
        HistoryEntry(id: id, cls: cls, time: time, title: title, titleVersion: titleVersion, sha256: sha256,
                     source: source, name: name, folder: folder, canonical: canonical)
    }
}
