import AppKit
import FMClipCore
import SwiftUI

/// The Settings window: appearance, the name of the uncategorized group, and the limit of the uncategorized entries.
/// Each change applies at once and goes to `settings.json` in the history folder. The CLI uses the same file.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    /// The limit in the field. It goes to the settings when it does not delete entries, or when the user says OK.
    @State private var limitDraft = ClipSettings.defaultUncategorizedLimit
    /// The limit that waits for the confirmation, and the number of entries that it deletes.
    @State private var pendingLimit: Int?
    @State private var pendingExcess = 0
    @State private var askLimit = false

    var body: some View {
        Form {
            Picker("Appearance:", selection: Binding(get: { model.settings.appearance }, set: { model.setAppearance($0) })) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.radioGroup)

            Divider().padding(.vertical, 4)

            TextField("Uncategorized group:", text: Binding(get: { model.settings.uncategorizedName },
                                                            set: { model.setUncategorizedName($0) }),
                      prompt: Text(ClipSettings.defaultUncategorizedName))
            Text("The name of the group for the entries in no folder. A blank name gives \"\(ClipSettings.defaultUncategorizedName)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                TextField("Uncategorized limit:", value: $limitDraft, format: .number.grouping(.never))
                    .frame(width: 180)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $limitDraft, in: ClipSettings.limitRange, step: 10)
                    .labelsHidden()
                Text("entries")
            }
            Text("When there are more uncategorized entries, the app deletes the oldest ones. Entries in folders do not count, and the app never deletes them. Now: \(model.uncategorizedCount) uncategorized.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { limitDraft = model.settings.uncategorizedLimit }
        .onChange(of: limitDraft) { proposeLimit($0) }
        // A change by the CLI (or a Cancel) puts the saved limit back in the field.
        .onChange(of: model.settings.uncategorizedLimit) { if pendingLimit == nil { limitDraft = $0 } }
        .alert("Delete the \(pendingExcess) oldest uncategorized entries?",
               isPresented: $askLimit) {
            Button("Cancel", role: .cancel) { cancelLimit() }
            Button("OK", role: .destructive) { confirmLimit() }
        } message: {
            Text("The new limit is lower than the number of uncategorized entries now. Entries in folders stay.")
        }
    }

    /// A new value in the field: keep it in the range, then save it, or ask first if it deletes entries.
    private func proposeLimit(_ value: Int) {
        let clamped = ClipSettings.clampLimit(value)
        if clamped != value { limitDraft = clamped; return }  // onChange calls again with the clamped value
        guard pendingLimit == nil, clamped != model.settings.uncategorizedLimit else { return }
        let excess = model.excess(forLimit: clamped)
        if excess > 0 {
            pendingExcess = excess
            pendingLimit = clamped
            askLimit = true
        } else {
            model.setUncategorizedLimit(clamped)
        }
    }

    private func confirmLimit() {
        guard let limit = pendingLimit else { return }
        pendingLimit = nil
        model.setUncategorizedLimit(limit)
    }

    /// Cancel: the old value comes back.
    private func cancelLimit() {
        guard pendingLimit != nil else { return }
        pendingLimit = nil
        limitDraft = model.settings.uncategorizedLimit
    }
}

/// File > Settings…: opens the Settings window. macOS 14 and later use `openSettings`. macOS 13 sends the
/// action of the standard Settings item.
struct SettingsMenuButton: View {
    var body: some View {
        if #available(macOS 14, *) {
            ModernSettingsButton()
        } else {
            Button("Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
        }
    }
}

@available(macOS 14, *)
private struct ModernSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") { openSettings() }
    }
}
