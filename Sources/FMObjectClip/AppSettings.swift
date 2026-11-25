import AppKit
import FMClipCore

/// The settings operations of the app. The Settings window (SettingsView) calls them.
/// Each change goes through the store: it locks the history, writes `settings.json` and applies a lower limit at once.
extension AppModel {
    /// The label of the group of the entries in no folder, and of that item in the Move to Folder menus.
    var uncategorizedName: String { settings.displayName }

    /// The number of uncategorized entries now.
    var uncategorizedCount: Int { entries.filter { $0.folder == nil }.count }

    /// The AppKit appearance of a settings value: nil (follow the system), Aqua or Dark Aqua.
    static func nsAppearance(for value: String) -> NSAppearance? {
        switch value {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    /// Applies the appearance of the settings to the app at once.
    func applyAppearance() {
        guard appliesAppearance, let app = NSApp else { return }
        app.appearance = Self.nsAppearance(for: settings.appearance)
    }

    func setAppearance(_ value: String) {
        updateSettings { $0.appearance = value }
    }

    /// Sets the name of the uncategorized group. A blank name shows the default name.
    func setUncategorizedName(_ name: String) {
        updateSettings { $0.uncategorizedName = name }
    }

    /// The number of uncategorized entries that this limit deletes. Ask the user before a value above 0.
    func excess(forLimit limit: Int) -> Int {
        max(0, uncategorizedCount - ClipSettings.clampLimit(limit))
    }

    /// Sets the limit of the uncategorized entries. A lower limit deletes the oldest uncategorized entries at once.
    func setUncategorizedLimit(_ limit: Int) {
        updateSettings { $0.uncategorizedLimit = ClipSettings.clampLimit(limit) }
    }

    private func updateSettings(_ change: (inout ClipSettings) -> Void) {
        guard let store else { return }
        do {
            let gone = try store.updateSettings(change)
            settings = store.settings
            if !gone.isEmpty { refresh() }
        } catch {
            errorMessage = "Cannot save the settings: \(error.localizedDescription)"
        }
    }
}
