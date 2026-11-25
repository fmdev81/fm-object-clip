import Foundation

/// The settings of the app and the CLI: the file `settings.json` in the history folder.
/// A missing key or a bad value gives the default. A missing or unknown file gives all the defaults.
public struct ClipSettings: Codable, Equatable, Sendable {
    /// The appearance values: "system", "light" and "dark".
    public static let appearances = ["system", "light", "dark"]
    public static let defaultAppearance = "system"
    public static let defaultUncategorizedName = "Uncategorized"
    public static let defaultUncategorizedLimit = 500
    /// The permitted values of the limit.
    public static let limitRange = 10...100_000

    /// "system", "light" or "dark".
    public var appearance: String
    /// The label of the group of the entries in no folder. Use `displayName` to show it.
    public var uncategorizedName: String
    /// The maximum number of uncategorized entries (entries in no folder). Entries in folders do not count.
    public var uncategorizedLimit: Int

    public init(appearance: String = ClipSettings.defaultAppearance,
                uncategorizedName: String = ClipSettings.defaultUncategorizedName,
                uncategorizedLimit: Int = ClipSettings.defaultUncategorizedLimit) {
        self.appearance = Self.appearances.contains(appearance) ? appearance : Self.defaultAppearance
        self.uncategorizedName = uncategorizedName
        self.uncategorizedLimit = Self.clampLimit(uncategorizedLimit)
    }

    enum CodingKeys: String, CodingKey {
        case appearance, uncategorizedName, uncategorizedLimit
    }

    /// Each key is optional. A value of the wrong type gives the default.
    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        self.init(appearance: (try? c?.decodeIfPresent(String.self, forKey: .appearance)) ?? Self.defaultAppearance,
                  uncategorizedName: (try? c?.decodeIfPresent(String.self, forKey: .uncategorizedName))
                      ?? Self.defaultUncategorizedName,
                  uncategorizedLimit: (try? c?.decodeIfPresent(Int.self, forKey: .uncategorizedLimit))
                      ?? Self.defaultUncategorizedLimit)
    }

    /// The name to show for the uncategorized group. A blank name gives the default name.
    public var displayName: String {
        HistoryStore.cleanName(uncategorizedName) ?? Self.defaultUncategorizedName
    }

    /// The limit of the text in the Settings field: a whole number (spaces and group separators are ignored),
    /// clamped to the permitted range. Nil when the text is not a number.
    public static func limit(fromText text: String) -> Int? {
        let digits = text.filter { !$0.isWhitespace && $0 != "," && $0 != "\u{00A0}" && $0 != "'" }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return clampLimit(n)
    }

    /// The limit in the permitted range.
    public static func clampLimit(_ n: Int) -> Int {
        min(max(n, limitRange.lowerBound), limitRange.upperBound)
    }

    // MARK: - Keys of the CLI

    /// The keys of `fm-object-clip-cli settings set KEY VALUE`, in the order of the output.
    public static let keys = ["appearance", "uncategorized-name", "uncategorized-limit"]

    public enum SettingError: Error, LocalizedError, Equatable {
        case unknownKey(String)
        case badValue(key: String, value: String)

        public var errorDescription: String? {
            switch self {
            case .unknownKey(let key):
                return "unknown setting \(key); use one of \(ClipSettings.keys.joined(separator: ", "))"
            case .badValue(let key, let value):
                switch key {
                case "appearance":
                    return "bad value \"\(value)\" for appearance; use one of \(ClipSettings.appearances.joined(separator: ", "))"
                case "uncategorized-limit":
                    return "bad value \"\(value)\" for uncategorized-limit; use a number from "
                        + "\(ClipSettings.limitRange.lowerBound) to \(ClipSettings.limitRange.upperBound)"
                default:
                    return "bad value \"\(value)\" for \(key)"
                }
            }
        }
    }

    /// Sets one value from text (the CLI). A bad key or value throws, and nothing changes.
    /// An empty name is permitted: the app then shows the default name.
    public mutating func set(_ key: String, to value: String) throws {
        switch key {
        case "appearance":
            let v = value.lowercased()
            guard Self.appearances.contains(v) else { throw SettingError.badValue(key: key, value: value) }
            appearance = v
        case "uncategorized-name":
            uncategorizedName = HistoryStore.cleanName(value) ?? ""
        case "uncategorized-limit":
            guard let n = Int(value.trimmingCharacters(in: .whitespaces)), Self.limitRange.contains(n) else {
                throw SettingError.badValue(key: key, value: value)
            }
            uncategorizedLimit = n
        default:
            throw SettingError.unknownKey(key)
        }
    }

    /// The value of a key as text (the CLI). The name shows as the app shows it.
    public func value(of key: String) -> String? {
        switch key {
        case "appearance": return appearance
        case "uncategorized-name": return displayName
        case "uncategorized-limit": return String(uncategorizedLimit)
        default: return nil
        }
    }
}

/// Reads and writes `settings.json` in a history folder. To change the settings, use `HistoryStore.updateSettings`:
/// it takes the lock of the history and applies the new limit at once.
public enum SettingsStore {
    public static func url(in folder: URL) -> URL {
        folder.appendingPathComponent("settings.json")
    }

    /// The settings in the folder. A missing or bad file gives the defaults. This is not an error.
    public static func load(from folder: URL) -> ClipSettings {
        guard let data = try? Data(contentsOf: url(in: folder)), !data.isEmpty,
              let settings = try? JSONDecoder().decode(ClipSettings.self, from: data) else { return ClipSettings() }
        return settings
    }

    /// Writes a temporary file, then moves it into place (atomic).
    public static func save(_ settings: ClipSettings, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: url(in: folder), options: .atomic)
    }
}

// MARK: - Settings of a history

extension HistoryStore {
    /// The settings in `settings.json` of this history (the defaults if the file is missing).
    public var settings: ClipSettings { SettingsStore.load(from: folder) }

    /// The number of uncategorized entries that a new limit deletes at once (0 if none).
    public func excess(forLimit limit: Int) -> Int {
        max(0, uncategorizedCount - ClipSettings.clampLimit(limit))
    }

    /// Changes the settings under the lock of the history, writes `settings.json`, and applies a lower limit at once.
    /// Returns the deleted entries. With a fixed limit (tests), a new limit also replaces the fixed limit.
    @discardableResult
    public func updateSettings(_ change: (inout ClipSettings) -> Void) throws -> [HistoryEntry] {
        try withLock {
            let oldLimit = limit
            var settings = self.settings
            change(&settings)
            settings = ClipSettings(appearance: settings.appearance, uncategorizedName: settings.uncategorizedName,
                                    uncategorizedLimit: settings.uncategorizedLimit)  // validate again
            try SettingsStore.save(settings, to: folder)
            if fixedLimit != nil { fixedLimit = settings.uncategorizedLimit }
            // Only a new limit deletes entries. An appearance or name change never does, even when a Merge or a
            // Replace left more uncategorized entries than the limit (the next capture trims them).
            guard limit != oldLimit else { return [] }
            let gone = trimToLimit()
            if !gone.isEmpty { try saveIndex() }
            return gone
        }
    }
}
