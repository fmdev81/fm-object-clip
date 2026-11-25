import AppKit
import FMClipCore
import SwiftUI

/// The Settings window: appearance, the name of the uncategorized group, and the limit of the uncategorized entries.
/// Each change applies at once and goes to `settings.json` in the history folder. The CLI uses the same file.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    /// The text in the limit field. It is proposed only when the user commits it (Return, or the field loses focus),
    /// so that typing "1000" over 500 never asks about "1".
    @State private var limitText = String(ClipSettings.defaultUncategorizedLimit)
    @FocusState private var limitFocused: Bool
    /// The limit that waits for the confirmation, and the number of entries that it deletes.
    @State private var pendingLimit: Int?
    @State private var pendingExcess = 0
    @State private var askLimit = false

    /// The width of the label column and of the control column. The window is their sum plus the padding.
    private static let labelWidth: CGFloat = 150
    private static let controlWidth: CGFloat = 290

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                label("Appearance:")
                Picker("Appearance:", selection: Binding(get: { model.settings.appearance }, set: { model.setAppearance($0) })) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider().gridCellColumns(2).padding(.vertical, 4)

            GridRow {
                label("Uncategorized group:")
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Uncategorized group", text: Binding(get: { model.settings.uncategorizedName },
                                                                   set: { model.setUncategorizedName($0) }),
                              prompt: Text(ClipSettings.defaultUncategorizedName))
                        .labelsHidden()
                    help("The name of the group for the entries in no folder. A blank name gives \"\(ClipSettings.defaultUncategorizedName)\".")
                }
            }

            GridRow {
                label("Uncategorized limit:")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        TextField("Uncategorized limit", text: $limitText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($limitFocused)
                            .onSubmit { commitLimitText() }
                        Stepper("Uncategorized limit", onIncrement: { step(10) }, onDecrement: { step(-10) })
                            .labelsHidden()
                        Text("entries")
                    }
                    help("When there are more uncategorized entries, the app deletes the oldest ones. Entries in folders do not count, and the app never deletes them. Now: \(model.uncategorizedCount) uncategorized.")
                }
            }
        }
        .padding(20)
        .frame(width: Self.labelWidth + Self.controlWidth + 10 + 40)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { limitText = String(model.settings.uncategorizedLimit) }
        // Focus loss commits the text, as Return does.
        .onChange(of: limitFocused) { focused in if !focused { commitLimitText() } }
        // A change by the CLI (or a Cancel) puts the saved limit back in the field.
        .onChange(of: model.settings.uncategorizedLimit) { value in if pendingLimit == nil { limitText = String(value) } }
        .alert("Delete the \(pendingExcess) oldest uncategorized entries?",
               isPresented: $askLimit) {
            Button("Cancel", role: .cancel) { cancelLimit() }
            Button("OK", role: .destructive) { confirmLimit() }
        } message: {
            Text("The new limit is lower than the number of uncategorized entries now. Entries in folders stay.")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .frame(width: Self.labelWidth, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    private func help(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: Self.controlWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Return or focus loss: propose the typed limit. Text that is not a number puts the saved limit back.
    private func commitLimitText() {
        guard let value = ClipSettings.limit(fromText: limitText) else {
            limitText = String(pendingLimit ?? model.settings.uncategorizedLimit)
            return
        }
        limitText = String(value)
        proposeLimit(value)
    }

    /// A stepper click: one step from the value in the field, proposed at once.
    private func step(_ delta: Int) {
        let base = ClipSettings.limit(fromText: limitText) ?? model.settings.uncategorizedLimit
        let value = ClipSettings.clampLimit(base + delta)
        limitText = String(value)
        proposeLimit(value)
    }

    /// A committed value: save it, or ask first if it deletes entries.
    private func proposeLimit(_ value: Int) {
        guard pendingLimit == nil, value != model.settings.uncategorizedLimit else { return }
        let excess = model.excess(forLimit: value)
        if excess > 0 {
            pendingExcess = excess
            pendingLimit = value
            askLimit = true
        } else {
            model.setUncategorizedLimit(value)
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
        limitText = String(model.settings.uncategorizedLimit)
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
