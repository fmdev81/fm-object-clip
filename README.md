# fm-object-clip

fm-object-clip is a clipboard history for FileMaker Pro objects on macOS. It is a small SwiftUI app and a command-line tool.

When you copy scripts, tables, fields or layout objects in FileMaker Pro, the app keeps a copy. Later you select an entry in the window, the app puts it on the clipboard again, and you paste it in FileMaker Pro with Cmd+V. Entries can have names and can be sorted into folders.

fm-object-clip is not a general clipboard history. It keeps only FileMaker objects. It never keeps plain text, and no setting changes this.

## Requirements

- macOS 13 or later. On macOS 26 and later the window uses Liquid Glass.
- FileMaker Pro for macOS, to copy and paste the objects.
- To build: Xcode 15 or later (Swift 5.9 or later), or the Xcode Command Line Tools.

## How it works

1. You copy objects in FileMaker Pro (for example, script steps in the Script Workspace, or fields in Manage Database).
2. The app sees the new clipboard contents. It keeps a copy in the history. It checks the clipboard (`NSPasteboard.changeCount`) every 0.4 seconds, because macOS does not send an event when the clipboard changes.
3. Later, you double-click the entry in the window, or select it and press Return. The app puts the object back on the clipboard with its FileMaker class.
4. In FileMaker Pro, you press Cmd+V.

Any other program that puts one of the classes below on the clipboard is captured the same way.

## Pasteboard classes

The app captures these FileMaker Pro classes and no others:

| Class | Objects | Label in the app |
|---|---|---|
| `XMSS` | Script steps | Scripts |
| `XMTB` | Tables | Tables |
| `XMFD` | Fields | Fields |
| `XML2` | Layout objects | Layout |

The pasteboard type of a class is `CorePasteboardFlavorType 0x` followed by the hex of the 4 ASCII letters. For example, the type of `XMSS` is `CorePasteboardFlavorType 0x584D5353`.

## Entry names

- Without a name, the title of an entry comes from its XML. For a script, it is the first comment that has text, and the count of steps.
- To give an entry a name, select **File** > **Rename…** (Cmd+R), or double-click the title in the detail pane. An empty name gives the automatic title again. `fm-object-clip-cli rename` and `fm-object-clip-cli add --name` also set a name.
- The name does not change the stored XML or the data that **Copy Entry** puts on the clipboard.

## Folders

Use folders to keep the entries of one project together. Folders are flat: a folder cannot hold a folder. An entry is in one folder or in no folder.

- The list on the left is a tree, as in the sidebar of the Finder. Each folder is a group row with a triangle, a folder icon, the name in bold and the number of entries. After the folders, the group **No Folder** has the entries that are in no folder. Thus each entry is under a group row.
- Click a group row to open or close the group. When the group is open, its entries show under it, with an indent and a thin vertical line. The app keeps the open groups between launches. **No Folder** is open at the first launch.
- The type filter and the search work on all the entries. While a filter or a search is active, the list shows only the folders that have a match, and these folders are open.
- If the list does not show the selected entry (after a filter, a search, or when you close its folder), the detail pane is empty.
- To make a folder, select **File** > **New Folder…** (Cmd+Shift+N), or right-click a folder row. A new folder is open.
- To move an entry to a folder, drag the entry to the folder row. To take an entry out of its folder, drag it to **No Folder**. You can also select **File** > **Move to Folder**, or right-click the entry and select **Move to Folder**. Select **No Folder** to take the entry out of its folder.
- To change the order of the folders, drag a folder row up or down. A line shows the new position: drop the folder on the upper half of a folder row to put it before that row, or on the lower half to put it after that row. Drop it on **No Folder** to put it last. You can also right-click the folder row and select **Move Folder Up** or **Move Folder Down**. **Edit** > **Undo** puts the folder back. The entries stay in their folders. **No Folder** is always after the folders, and you cannot drag it. The order stays after a restart, and the CLI command `folders` shows the same order.
- To rename or delete a folder, right-click the folder row. You can also click the folder row and then select **File** > **Rename Folder…** or **Delete Folder**.
- When you delete a folder, its entries stay in the history, in no folder.
- The folder does not change the stored XML or the data that **Copy Entry** puts on the clipboard.

## History

The history is in `~/Library/Application Support/fm-object-clip/history/`. Your history can contain the names and logic of your FileMaker solutions, so do not commit it to a public repository.

- Each entry is one file, `<id>.xml`. The file has the clipboard data as UTF-8 XML, with no changes.
- The file `index.json` has one item for each entry, with these fields:

| Field | Value |
|---|---|
| `id` | An id that is different for each entry. It is also the name of the `.xml` file. |
| `class` | `XMSS`, `XMTB`, `XMFD` or `XML2` |
| `time` | The time of the capture, in ISO 8601 |
| `title` | A short name from the XML. For a script: the first comment that has text, and the count of steps. If no comment has text, the first step that does something (not `Set Error Capture`, `Allow User Abort`, `Freeze Window` or `Enter Browse Mode`), as a short preview. |
| `titleVersion` | The version of the title rules. When the rules change, the app or the CLI makes the title again one time for each entry. |
| `sha256` | The hash of the data |
| `source` | `clipboard`, or `cli` for an entry from `fm-object-clip-cli add` |
| `name` | Optional. The name from **Rename** or from `fm-object-clip-cli add --name`. The window shows it in place of `title`. |
| `folder` | Optional. The folder of the entry. |
| `canonical` | The SHA-256 of the canonical XML, for the duplicate check. An entry from an earlier version can have no value. The app adds it when it needs it. |

- The file `folders.json` has the names of the folders, also the empty folders, in the order of the list.
- The file `.last-restore.json` has the class and the hashes of the last entry that **Copy Entry** or `fm-object-clip-cli restore` put on the clipboard. When the clipboard gets other contents, the app deletes the file.
- The history keeps 200 entries. When a new entry goes over the limit, the app or the CLI deletes the oldest entry that is in no folder. The app does not delete an entry that is in a folder.
- If a new capture has the same class and the same content as an entry, the app does not add a new entry. It moves the old entry to the top, and the entry keeps the bytes of the first capture. The same content is the same bytes, or the same canonical XML.
- A copy from the app (**Copy Entry**) or from `fm-object-clip-cli restore` does not change the entry. The entry keeps its time and its place. When you paste, FileMaker Pro can put the same object on the clipboard again. The app does not move the entry for this capture. The rule stops when the clipboard gets other contents. Then an identical copy in FileMaker Pro moves the entry to the top again.
- The canonical XML does not include these items:
  - the XML declaration
  - the whitespace between elements
  - the order of the attributes
  - character references
  - the form of empty elements (`<a/>` or `<a></a>`)
- FileMaker Pro can put one script on the clipboard two times, a few seconds apart. First it puts compact XML. Then it puts pretty-printed XML with a declaration and a text flavor. The two captures give one entry.

The files are plain XML and JSON. Scripts and agents can read them without the app.

## Main window

- A list of the entries. The list has a fixed width. The selected entry has a light tint. The order of the entries in each group is:
  - In a folder where each entry has a name: the order of the names. Numbers in a name are in the natural order, for example "2" before "10". Thus the entries "01 …" to "17 …" stay in their order.
  - In a folder where one or more entries have no name: the newest entry at the top.
  - In **No Folder**: the newest entry at the top.
- Each entry row has one line: a small colored badge for the type, the title (the name, else the automatic title), and a short time. The badge colors are Scripts (blue), Tables (purple), Fields (green) and Layout (orange).
- The short time is the time for an entry of today, "Yesterday", or a short date, for example "Nov 18". A date of an earlier year also has the year. The detail pane and the tooltip of a row show the full date and time.
- A filter by class: All, Scripts, Tables, Fields, Layout.
- A search field. It finds text in the name, in the automatic title and in the XML.
- The header has the type filter and the search field only. The operations on an entry are in the **File** menu.
- **File** > **Copy Entry** (Cmd+C): puts the selected entry on the clipboard with its class. A double-click and the Return key do the same. A copy from the app does not make a new entry, and it does not change the time or the place of the entry. For approximately 1 second, the row shows a green check mark and "Copied" in place of the time.
- The Up Arrow and Down Arrow keys move the selection, also while you type in the search field. From the search field, they also move the keyboard focus to the list.
- The Delete key deletes the selected entries when the list has the keyboard focus. In the search field, the Delete key changes the text. When the app starts, the list has the keyboard focus. A click on a row also gives the focus to the list.
- The Left Arrow key closes the group of the selected entry, or the selected group. The Right Arrow key opens the selected group.
- **File** > **Delete** (Cmd+Delete): removes the selected entries from the history. With more than one entry selected, the menu item shows the number, for example "Delete 12 Entries…". To put them back, select **Edit** > **Undo** (Cmd+Z). One Undo puts back all the entries of one delete.
- To select more than one entry:
  - Cmd+click an entry to add it to the selection, or to remove it.
  - Shift+click an entry to select all the entries from the last click to that entry, in the order of the list.
  - Shift+Up Arrow and Shift+Down Arrow make the selection larger or smaller.
  - Cmd+A or **Edit** > **Select All** selects all the entries that the list shows. It does not select a folder row, or an entry in a closed folder. In the search field, Cmd+A selects the text.
- With more than one entry selected:
  - The Delete key, **File** > **Delete** and **Edit** > **Delete** delete all the selected entries. First the app asks, for example "Delete 12 entries?". Press Return to delete, or Escape to cancel.
  - **File** > **Move to Folder** moves all the selected entries.
  - The detail pane shows the number of entries and the number of each type. **Copy Entry**, **Rename…** and **Save As…** are not available.
- Right-click an entry, or Control-click it, to open its context menu. The menu obeys the same rule as the Finder:
  - If the entry is in the selection, the selection does not change. Each item acts on all the selected entries. **Delete** shows the number, for example "Delete 12 Entries…", and the app asks first. **Move to Folder** moves all the selected entries. **Copy**, **Rename…** and **Save As…** are not available.
  - If the entry is not in the selection, the app selects only that entry. Each item acts on that entry.
- **File** > **Save As…** (Cmd+Shift+S): saves the XML of the selected entry to a file.
- A short summary of the selected entry, only to recognize it. For a script, the summary has one line for each step: the step name and the first thing that the step acts on. This is the first field (`Contacts::Company`), else the variable, else the first line of the first calc, else a layout or a script name. The app cuts it at 80 characters. Examples: `Set Field [ Contacts::Company … ]`, `Set Variable [ $count … ]`, `If [ IsEmpty ( $x ) … ]`. If and Loop blocks have an indent. A comment shows its text. A disabled step starts with `//`. For tables, the summary shows each table and its fields. For fields, it shows the name, the type and the options of each field. For layout objects, it shows the number of objects of each type and the field names. The **Show XML** switch shows the full XML. The view indents the XML and shows it in colors. This is for display only: the history, **Copy Entry** and **Save As…** use the bytes as captured. You cannot change the XML.

On macOS 26 and later, the toolbar and the header of the detail pane use Liquid Glass. On macOS 13 to 15, they use a translucent material.

When you close the window, the app continues to watch the clipboard. To open the window again, click the Dock icon, or select **Window** > **History Window** (Cmd+0). To stop the app, press Cmd+Q.

## Menus

| Menu | Items |
|---|---|
| fm-object-clip | About fm-object-clip, Quit (Cmd+Q) |
| File | Entries: Copy Entry (Cmd+C), Rename… (Cmd+R), Move to Folder, Save As… (Cmd+Shift+S), Delete (Cmd+Delete). Folders: New Folder… (Cmd+Shift+N), Rename Folder…, Delete Folder. Then Close Window (Cmd+W). |
| Edit | The standard items. When the list has the keyboard focus, **Select All** (Cmd+A) and **Delete** act on the entries. |
| View | All Types (Cmd+1), Scripts (Cmd+2), Tables (Cmd+3), Fields (Cmd+4), Layout (Cmd+5), Show XML (Cmd+Option+X) |
| Window | History Window (Cmd+0) and the standard items |
| Help | fm-object-clip Help: opens this README on GitHub |

NOTE: When an entry is selected, Cmd+C copies the entry, also when you select text in the XML view. To copy selected text, use **Edit** > **Copy**.

## Build and install

Clone the repository and run the commands in its root folder.

```bash
swift build          # debug build
swift test           # the tests
swift run FMObjectClip
```

The tests use a private pasteboard and a temporary folder. They do not change your clipboard or your history.

### The app bundle

```bash
scripts/make-app.sh
```

The script builds the release binaries. It puts the app in `build/FMObjectClip.app` (bundle ID `com.solutionscay.fm-object-clip`), with an `Info.plist` and the icon. It puts the command-line tool in `build/bin/fm-object-clip-cli` and in `build/FMObjectClip.app/Contents/MacOS/fm-object-clip-cli`. Git ignores `build/`.

The script also writes the SDK version into the binary, because SwiftPM writes the deployment target (13.0) there. Without the SDK version, macOS 26 shows the app without Liquid Glass.

The binary has an ad hoc signature, because Apple silicon runs only signed code. The bundle has no Developer ID signature and is not notarized. To open the app, double-click `build/FMObjectClip.app` in Finder, or run `open build/FMObjectClip.app`. If macOS does not open the app the first time, right-click the app and select **Open**. To install it, copy `build/FMObjectClip.app` to `/Applications`.

### The icon

The icon is `Resources/AppIcon.icns`. `scripts/make-icon.swift` draws it, and `scripts/make-icon.sh` makes the `.icns` file with `sips` and `iconutil`. To change the icon, change `make-icon.swift` and run `scripts/make-icon.sh`.

### Package layout

One Swift package (`Package.swift`) with 3 targets and the test target `FMClipCoreTests`:

| Target | Type | What it does |
|---|---|---|
| `FMClipCore` | Library | Reads and writes the pasteboard classes. Keeps the history. |
| `fm-object-clip-cli` | Command-line tool | Reads and manages the history, for scripts and agents. |
| `FMObjectClip` | App (SwiftUI) | The main window and the menus |

## Command-line tool

`fm-object-clip-cli` reads and manages the history from a terminal, a script or an agent. Use `build/bin/fm-object-clip-cli`, or `build/FMObjectClip.app/Contents/MacOS/fm-object-clip-cli` inside the app bundle.

### Safe while the app runs

The app and the tool can change the history at the same time. Each change locks the history (the file `.lock` in the history folder), reads the latest `index.json` and `folders.json`, and writes the files atomically. The app sees each change on disk and shows it at once.

### Commands

Each command takes `--history DIR` (the default is the history of the app) and `--json`. The IDs come from `list`.

| Command | What it does |
|---|---|
| `list [--folder NAME \| --no-folder] [--class C] [--search TEXT] [--limit N]` | The entries, newest first. The search looks in the name, the automatic title and the XML. |
| `show ID` | The data of one entry. |
| `xml ID` | The stored XML bytes, to stdout. |
| `folders` | The folders, in the order of the list, and the number of entries in each. |
| `info` | The FileMaker objects on the clipboard now. |
| `add FILE.xml --class C [--name NAME] [--folder NAME]` | Adds an entry from a file, with the rules of a capture. If the class and the XML are the same as an entry, it updates the name and the folder of that entry. |
| `restore ID` | Puts the entry on the clipboard with its class. The entry keeps its time and its place. |
| `rename ID NAME` | Gives the entry a name. `""` gives the automatic title again. |
| `move ID FOLDER` | Moves the entry to the folder. The tool makes the folder if necessary. |
| `move ID --no-folder` | Takes the entry out of its folder. |
| `delete ID [ID ...]` | Deletes the entries. If an ID does not exist, the tool deletes nothing. |
| `folder new NAME` | Makes a folder. |
| `folder rename OLD NEW` | Renames a folder. Its entries go with it. |
| `folder delete NAME` | Deletes a folder. Its entries go to No Folder. |
| `folder move NAME POSITION` | Moves a folder to a position in the list. Position 1 is the first. A position after the end puts the folder last. Its entries stay in it. It shows the folders in the new order. |
| `watch` | Adds each FileMaker object on the clipboard to the history, without the app. |
| `help`, `--help` | Shows the help. |

`C` is `XMSS`, `XMTB`, `XMFD` or `XML2`.

### JSON

With `--json`, the read commands give an entry or a list of entries. The write commands give the changed entry or folder. `delete` gives the deleted entries. The field names are stable:

| Field | Value |
|---|---|
| `id` | The id of the entry |
| `class` | `XMSS`, `XMTB`, `XMFD` or `XML2` |
| `type` | `Scripts`, `Tables`, `Fields` or `Layout` |
| `title` | The title that the app shows: the name, else the automatic title |
| `autoTitle` | The title from the XML |
| `name` | The name, or `null` |
| `folder` | The folder, or `null` |
| `time` | The time of the last capture, ISO 8601 |
| `sha256` | The hash of the XML |
| `source` | `clipboard`, or `cli` for `add` |
| `bytes` | The size of the XML file |
| `file` | The path of the XML file |
| `canonical` | The SHA-256 of the canonical XML. Two entries with the same class and the same value are the same object. |

A folder is `{"name", "count"}`. `folder rename` also gives `oldName`. `folder delete` gives `{"name", "movedEntries"}`. `folder move` gives the list of folders in the new order. `info` gives `{"class", "bytes"}` for each object.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | OK |
| 1 | Error, for example a folder name that exists |
| 2 | Bad usage, for example an unknown command or class |
| 3 | Not found: an entry, a folder or a file |

The tool writes errors to stderr.

### Examples

```bash
CLI=build/bin/fm-object-clip-cli
$CLI list --folder "Project A" --json
$CLI xml 20261120-180123-0f558176 > fields.xml
$CLI restore 20261120-180123-0f558176
$CLI move 20261120-180123-0f558176 "Project A"
$CLI folder new "Project B"
$CLI add contacts-fields.xml --class XMFD --name "Contact fields" --folder "Project A"
```

## Limits

- The app captures only the 4 classes above. It does not capture plain text or other FileMaker classes, for example whole scripts, custom functions or value lists.
- You cannot change the XML in the app.
- The app does not paste into FileMaker Pro. You press Cmd+V.
- The app is for macOS only. FileMaker Pro for Windows uses different clipboard formats.

## License

fm-object-clip is open source under the [MIT License](LICENSE). Copyright (c) 2026 Solutions Cay LLC.
