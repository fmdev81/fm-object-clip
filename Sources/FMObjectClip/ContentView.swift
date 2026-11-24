import FMClipCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?

    /// The list has a fixed width: no divider to drag, no sidebar to collapse.
    static let listWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 0) {
            list
                .background(ListKeyResponder(model: model))
                .frame(width: Self.listWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarBackground())
            Divider().opacity(0.4)
            detail
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(HiddenWindowTitle())
        .modifier(NoToolbarTitle())
        .onAppear {
            AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") }
            model.undoManager = undoManager
            // At launch the list has the keyboard focus, not the search field.
            DispatchQueue.main.async { model.focusList() }
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Class", selection: $model.filter) {
                    Text("All").tag(FMClass?.none)
                    ForEach(FMClass.allCases, id: \.self) { Text($0.label).tag(FMClass?.some($0)) }
                }
                .pickerStyle(.segmented)
                .help("Filter by class")
            }
        }
        .alert(model.prompt?.title ?? "", isPresented: Binding(get: { model.prompt != nil }, set: { if !$0 { model.prompt = nil } })) {
            TextField("Name", text: $model.promptText)
            Button(model.prompt?.button ?? "OK", action: model.finishPrompt)
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.prompt = nil }
        } message: {
            Text(model.prompt?.message ?? "")
        }
        .alert("fm-object-clip", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - List

    /// One list (a tree): each folder is a row with a disclosure triangle, and its entries show indented under it
    /// when it is expanded. The entries in no folder come after the folders.
    /// Custom rows instead of List, so that the selection is a soft tint and not the accent fill.
    /// Click selects, double-click copies. The key monitor gives Up, Down, Return and Delete.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        switch row.kind {
                        case .folder(let name, let count, let expanded):
                            GroupRow(folder: name, count: count, expanded: expanded, filtering: model.isFiltering,
                                     first: row.id == model.rows.first?.id)
                        case .noFolder(let count, let expanded):
                            GroupRow(folder: nil, count: count, expanded: expanded, filtering: model.isFiltering,
                                     first: row.id == model.rows.first?.id)
                        case .entry(let entry, let indented):
                            entryRow(entry, indented: indented)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: model.listSelection.focus) { id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            .overlay {
                if model.rows.isEmpty {
                    Text(model.entries.isEmpty && model.folders.isEmpty
                         ? "No FileMaker objects yet.\nCopy scripts, tables, fields or layout objects in FileMaker Pro."
                         : "No entries match.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private func entryRow(_ entry: HistoryEntry, indented: Bool) -> some View {
        EntryRow(entry: entry, selected: model.isSelected(entry.id), indented: indented, copied: model.copiedID == entry.id)
            .id(entry.id)
            .onDrag { NSItemProvider(object: entry.id as NSString) }
            .onTapGesture(count: 2) {
                // A double-click copies; not while Cmd or Shift is down (then the clicks change the selection).
                if NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty { model.copy(entry) }
            }
            .simultaneousGesture(TapGesture().onEnded {
                model.click(entry.id, modifiers: NSEvent.modifierFlags)
                model.focusList()  // leave the search field or the XML view: Cmd+A and Delete now act on the list
            })
            .onHover { inside in
                // The key monitor reads this row on a right-click, before the context menu opens.
                if inside { model.hoveredEntry = entry.id } else if model.hoveredEntry == entry.id { model.hoveredEntry = nil }
            }
            // The Finder rule: if the row is in the selection, each item acts on all the selected entries.
            .contextMenu {
                let many = model.contextActsOnMany(entry.id)
                Button("Copy") { model.contextCopy(entry.id) }.disabled(many)
                Button("Rename…") { model.contextRename(entry.id) }.disabled(many)
                MoveToFolderMenu(entry: entry)
                Button("Save As…") { model.contextSave(entry.id) }.disabled(many)
                Divider()
                Button(model.contextDeleteTitle(for: entry.id)) { model.contextDelete(entry.id) }
            }
    }

    /// A right-click or a Control-click on an entry row, before the context menu opens (the Finder rule): if the row
    /// is not in the selection, only this row is selected. A selection that contains the row does not change.
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        let model = model
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            guard let window = event.window, !(window is NSPanel), window.attachedSheet == nil,
                  let id = model.hoveredEntry else { return event }
            model.contextClick(id)
            model.focusList()
            return event
        }
    }

    /// Up and Down move the selection and Return copies the entry, also while you type in the search field.
    /// Left closes the group of the selected entry (or the selected group). Right opens the selected group.
    /// Delete deletes the entry when no text field has the keyboard focus.
    /// The monitor does nothing when the XML view has the focus, or when Command, Option or Control is down.
    private func installKeyMonitor() {
        installMouseMonitor()
        guard keyMonitor == nil else { return }
        let model = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Not in a dialog, a panel (alert, Save As) or a sheet, and not while the Rename dialog is open.
            guard let window = event.window, window.isKeyWindow, !(window is NSPanel), window.sheetParent == nil,
                  window.attachedSheet == nil, model.prompt == nil else { return event }
            let text = window.firstResponder as? NSTextView
            if let text, !text.isFieldEditor { return event }  // the XML view
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Cmd+A in the list selects all the visible entries. In the search field it selects the text.
            if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "a" {
                guard text == nil else { return event }
                model.selectAll()
                return nil
            }
            guard mods.intersection([.command, .option, .control]).isEmpty else { return event }
            let shift = mods.contains(.shift)
            switch event.keyCode {
            case 125, 126:
                model.moveSelection(by: event.keyCode == 125 ? 1 : -1, extend: shift)
                // From the search field, the arrows move into the list, so that Cmd+A and Delete act on the entries.
                if text != nil { model.focusList() }
            case 36, 76:
                guard model.selected != nil else { return event }
                model.copySelected()
            case 51, 117:
                // In the search field, Delete edits the text.
                guard text == nil, model.canDeleteSelection else { return event }
                model.deleteSelected()
            case 123:
                guard text == nil else { return event }  // in the search field, the arrows move the cursor
                withAnimation(.easeOut(duration: 0.15)) { model.collapseCurrentGroup() }
            case 124:
                guard text == nil else { return event }
                withAnimation(.easeOut(duration: 0.15)) { model.expandCurrentGroup() }
            default: return event
            }
            return nil
        }
    }


    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if model.listSelection.count > 1 {
            MultiSelectionSummary(entries: model.selectedEntries)
        } else if let entry = model.selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TypeBadge(cls: entry.cls)
                    Text(entry.displayTitle).font(.headline).lineLimit(1)
                        .onTapGesture(count: 2, perform: model.startRename)
                        .help("Double-click to rename")
                    Spacer()
                    Text(Self.displayTime(entry.time)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Toggle("Show XML", isOn: $model.showXML).toggleStyle(.switch).controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassPanel(cornerRadius: 14)

                VStack(alignment: .leading, spacing: 0) {
                    if !model.showXML, let summary = model.summary(for: entry) {
                        CodeTextView(text: XMLHighlighter.plain(summary))
                    } else {
                        if !model.showXML {
                            Text("Cannot make a summary of this entry. This is the XML.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                        CodeTextView(text: model.formattedXML(for: entry))
                    }
                }
                .contentPanel(cornerRadius: 14)
            }
            .padding(12)
        } else {
            Text("Select an entry.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The short time for a row (see ShortTime in FMClipCore).
    static func shortTime(_ iso: String) -> String {
        ShortTime.parse(iso).map { ShortTime.format($0) } ?? iso
    }

    /// The full date and time, for the detail pane and the tooltip of a row.
    static func displayTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

/// One compact entry row: a small type badge, the name, and a short time on the right.
/// An entry under a group row has an indent and a thin vertical guide line, so you can see the group it is in.
struct EntryRow: View {
    let entry: HistoryEntry
    let selected: Bool
    var indented = true
    /// True for about one second after a copy of this entry: the row shows "Copied" in place of the time.
    var copied = false
    @State private var hover = false

    static let guideX: CGFloat = 17
    static let indent: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            TypeBadge(cls: entry.cls, compact: true)
            Text(entry.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            } else {
                Text(ContentView.shortTime(entry.time))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RowBackground(selected: selected, hover: hover, cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.leading, indented ? Self.indent : 0)
        .padding(.vertical, 1)
        .background(alignment: .leading) {
            if indented {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, Self.guideX)
            }
        }
        .onHover { hover = $0 }
        .help("\(entry.cls.label) · \(entry.displayTitle)\n\(ContentView.displayTime(entry.time))")
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}

/// A group row, like a Finder or Mail sidebar section: triangle, icon, semibold name and number of entries.
/// It is a folder, or the group "No Folder" (folder == nil) for the entries in no folder.
/// A click on the row opens or closes the group. A click on a folder row also selects it for the File menu.
/// Right-click a folder row to rename or delete it. Drop an entry on a group row to move it to that folder, or to no folder.
struct GroupRow: View {
    @EnvironmentObject var model: AppModel
    let folder: String?
    let count: Int
    let expanded: Bool
    /// While a filter or a search is active, the group shows expanded and a click does not collapse it.
    let filtering: Bool
    /// The first row of the list has less space above it.
    let first: Bool
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 12)
            Image(systemName: folder == nil ? "tray" : (expanded ? "folder.fill" : "folder"))
                .foregroundStyle(folder == nil ? Color.secondary : Color.accentColor.opacity(0.85))
                .frame(width: 18)
            Text(folder ?? "No Folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(folder == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RowBackground(selected: (folder != nil ? model.selectedFolder == folder : model.selectedNoFolder) || targeted,
                                  hover: hover, cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.top, first ? 0 : 10)
        .padding(.bottom, 2)
        .onHover { hover = $0 }
        .onTapGesture {
            model.selection = nil
            if let folder { model.selectedFolder = folder } else { model.selectedFolder = nil; model.selectedNoFolder = true }
            model.focusList()
            guard !filtering else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if let folder { model.toggleFolder(folder) } else { model.noFolderExpanded.toggle() }
            }
        }
        .contextMenu {
            if let folder {
                Button("Rename Folder…") { model.startRenameFolder(folder) }
                Button("Delete Folder") { model.deleteFolder(folder) }
                Divider()
            }
            Button("New Folder…") { model.startNewFolder() }
        }
        .onDrop(of: [.plainText, .text], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = object as? String else { return }
                DispatchQueue.main.async { model.move(id, to: folder) }
            }
            return true
        }
        .help(expanded ? "Click to collapse" : "Click to expand")
    }
}

/// The Move to Folder menu for an entry: No Folder, each folder, and New Folder.
struct MoveToFolderMenu: View {
    @EnvironmentObject var model: AppModel
    let entry: HistoryEntry

    /// The menu moves all the selected entries if this entry is in the selection (the Finder rule).
    var body: some View {
        let targets = model.contextTargets(for: entry.id)
        Menu("Move to Folder") {
            Button("No Folder") { model.contextMove(entry.id, to: nil) }
                .disabled(targets.allSatisfy { $0.folder == nil })
            if !model.folders.isEmpty { Divider() }
            ForEach(model.folders, id: \.self) { folder in
                Button(folder) { model.contextMove(entry.id, to: folder) }
                    .disabled(targets.allSatisfy { $0.folder == folder })
            }
            Divider()
            Button("New Folder…") { model.contextNewFolder(entry.id) }
        }
    }
}

/// The detail pane when more than one entry is selected: the number of entries and the counts by type.
struct MultiSelectionSummary: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(entries.count) entries selected").font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(FMClass.allCases, id: \.self) { cls in
                    let n = entries.filter { $0.cls == cls }.count
                    if n > 0 {
                        HStack(spacing: 4) {
                            TypeBadge(cls: cls)
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Delete: press Delete, or select File > Delete.\nMove: select File > Move to Folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .glassPanel(cornerRadius: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard focus of the list

/// An invisible view behind the list that takes the keyboard focus for the list. With it as the first responder:
/// - Edit > Select All (Cmd+A) sends selectAll: here, and selects all the visible entries.
/// - Edit > Delete sends delete: here, and deletes the selected entries.
/// - The search field does not have the focus, so Cmd+A and Delete act on the entries, not on the search text.
final class ListKeyView: NSView, NSMenuItemValidation {
    weak var model: AppModel?

    override var acceptsFirstResponder: Bool { true }

    override func selectAll(_ sender: Any?) {
        model?.selectAll()
    }

    @objc func delete(_ sender: Any?) {
        model?.deleteSelected()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectAll(_:)): return !(model?.visibleIDs.isEmpty ?? true)
        case #selector(delete(_:)): return model?.canDeleteSelection ?? false
        default: return true
        }
    }
}

struct ListKeyResponder: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> ListKeyView {
        let view = ListKeyView()
        view.model = model
        model.listKeyView = view
        return view
    }

    func updateNSView(_ view: ListKeyView, context: Context) {
        view.model = model
        model.listKeyView = view
    }
}
