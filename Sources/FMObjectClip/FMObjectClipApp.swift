import AppKit
import FMClipCore
import SwiftUI

@main
struct FMObjectClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("fm-object-clip", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 440)
        }
        .commands { ClipCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opens the main window. ContentView sets it when the window appears the first time.
    static var openMainWindow: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // With `swift run` the app has no bundle: make it a normal app with a Dock icon. Do this before the launch
        // ends, so that SwiftUI installs its menu bar. FMObjectClip.app has a bundle and does not need it.
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app continues to watch the clipboard when you close the window. Click the Dock icon, or use the Window menu,
    /// to open the window again. Press Cmd+Q to quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A click on the Dock icon opens the window again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openMainWindow?() }
        return true
    }
}

/// The menu bar: File, Edit (standard), View (filter by type), Window (standard) and Help.
struct ClipCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About fm-object-clip") { model.showAbout() }
        }
        CommandGroup(replacing: .newItem) {
            Button("Copy Entry", action: model.copySelected)
                .keyboardShortcut("c")
                .disabled(model.selected == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Rename…", action: model.startRename)
                .keyboardShortcut("r")
                .disabled(model.selected == nil)
            Menu("Move to Folder") {
                Button("No Folder") { model.moveSelected(to: nil) }
                    .disabled(model.selectedEntries.allSatisfy { $0.folder == nil })
                if !model.folders.isEmpty { Divider() }
                ForEach(model.folders, id: \.self) { folder in
                    Button(folder) { model.moveSelected(to: folder) }
                        .disabled(model.selectedEntries.allSatisfy { $0.folder == folder })
                }
                Divider()
                Button("New Folder…") { model.startNewFolder(moveSelected: true) }
            }
            .disabled(model.selectedEntries.isEmpty)
            Button("Save As…", action: model.saveSelected)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selected == nil)
            Button(model.deleteMenuTitle, action: model.deleteSelected)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canDeleteSelection)
            Divider()
            Button("New Folder…") { model.startNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Rename Folder…") { if let f = model.selectedFolder { model.startRenameFolder(f) } }
                .disabled(model.selectedFolder == nil)
            Button("Delete Folder") { if let f = model.selectedFolder { model.deleteFolder(f) } }
                .disabled(model.selectedFolder == nil)
            Divider()
            BackupMenuItems(model: model)
            Divider()
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        CommandGroup(before: .toolbar) {
            filterItem("All Types", nil, "1")
            filterItem(FMClass.XMSS.label, .XMSS, "2")
            filterItem(FMClass.XMTB.label, .XMTB, "3")
            filterItem(FMClass.XMFD.label, .XMFD, "4")
            filterItem(FMClass.XML2.label, .XML2, "5")
            Divider()
            Toggle("Show XML", isOn: $model.showXML)
                .keyboardShortcut("x", modifiers: [.command, .option])
            Divider()
        }
        CommandGroup(before: .windowArrangement) {
            Button("History Window") { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("fm-object-clip Help") { model.openHelp() }
        }
    }

    private func filterItem(_ title: String, _ cls: FMClass?, _ key: KeyEquivalent) -> some View {
        Toggle(title, isOn: Binding(get: { model.filter == cls }, set: { if $0 { model.filter = cls } }))
            .keyboardShortcut(key)
    }
}
