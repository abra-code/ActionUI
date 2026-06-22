// Fixed ActionUISwiftTestApp.swift

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

import SwiftUI
import ActionUI
import ActionUISwiftAdapter

// Custom logger
final class CustomLogger: ActionUI.ActionUILogger {
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        print("[ActionUI][\(level)] \(message)")
    }
}

@main
struct ActionUISwiftTestApp: App {
    let logger = CustomLogger()

    // Runtime check for multi-window support
    private var supportsMultipleWindows: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsMultipleScenes
        #else
        return true // macOS supports multiple windows
        #endif
    }
    
    // Check for reset launch argument
    private var shouldResetState: Bool {
        CommandLine.arguments.contains("-resetAppState")
    }
    
    // Environment to manage windows
    @Environment(\.openWindow) private var openWindow
    
    init() {
        // Configure logger
        ActionUISwift.setLogger(logger)
        // receiving actionID, windowUUID, viewID, viewPartID, and optional context
        ActionUISwift.setDefaultActionHandler({actionID, windowUUID, viewID, viewPartID, context in
            print("Default action callback for actionID:\(actionID), windowUUID: \(windowUUID), viewID: \(viewID), viewPartID: \(viewPartID), context: \(String(describing: context))")
        })
        
        // Table demo handlers
        var tableAppendIndex = 0
        let tableExtraRows: [[String]] = [
            ["Frank Chen",    "Director",  "Operations"],
            ["Grace Kim",     "Lead",      "Platform"],
            ["Henry Wu",      "Intern",    "Data"]
        ]
        ActionUISwift.registerActionHandler(actionID: "table.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [
                ["Alice Johnson", "Engineer",  "Platform"],
                ["Bob Smith",     "Designer",  "Product"],
                ["Carol White",   "Manager",   "Engineering"],
                ["David Lee",     "Analyst",   "Data"],
                ["Eva Martinez",  "Engineer",  "Platform"]
            ])
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.append") { _, windowUUID, _, _, _ in
            let row = tableExtraRows[tableAppendIndex % tableExtraRows.count]
            tableAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [row])
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 1)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: (none)")
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.selection.changed") { _, windowUUID, _, _, _ in
            if let selected = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String], !selected.isEmpty {
                print("Table row selected: \(selected)")
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Selected: \(selected.joined(separator: " / "))")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: (none)")
            }
        }
        // Programmatic selection demos — none of these fire table.demo.selection.changed,
        // so each handler updates the status label itself to reflect the result.
        ActionUISwift.registerActionHandler(actionID: "table.demo.select.index") { _, windowUUID, _, _, _ in
            if let row = ActionUISwift.selectElementRow(windowUUID: windowUUID, viewID: 1, index: 2) {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Selected row #3 by index: \(row.joined(separator: " / "))")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Row #3 unavailable — load the data first.")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.select.content") { _, windowUUID, _, _, _ in
            // Match "Engineer" in the Role column only (0-based column 1).
            if let index = ActionUISwift.selectElementRow(windowUUID: windowUUID, viewID: 1, matching: "Engineer", column: 1) {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Matched \"Engineer\" in Role at row #\(index + 1).")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "No row with \"Engineer\" in the Role column.")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "table.demo.deselect") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementSelection(windowUUID: windowUUID, viewID: 1)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selection cleared.")
        }
        // Double-click demo: the framework routes a row double-click (and Return on a
        // selected row) through the Table's primaryAction. The action context is the
        // 0-based row index; the double-clicked row is the current selection.
        ActionUISwift.registerActionHandler(actionID: "table.demo.double.click") { _, windowUUID, _, _, context in
            let index = context as? Int ?? -1
            let row = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String] ?? []
            print("Double-click action executed: table.demo.double.click — row \(index): \(row.joined(separator: " / "))")
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                value: "Double-clicked row \(index): \(row.joined(separator: " / "))")
        }

        // List demo handlers
        var listAppendIndex = 0
        let listExtraItems = ["Haskell", "Elixir", "Julia", "Zig", "Dart"]
        ActionUISwift.registerActionHandler(actionID: "list.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [
                ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"], ["Go"]
            ])
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
        }
        // Pull-to-refresh: the List's onRefreshActionID fires this on a pull. We simulate an
        // async fetch — the spinner stays up until we deliver rows, since setElementRows
        // targeting the refreshing list ends the refresh (no explicit "done" call needed).
        ActionUISwift.registerActionHandler(actionID: "list.demo.refresh") { _, windowUUID, viewID, _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let stamp = Date().formatted(date: .omitted, time: .standard)
                ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: [
                    ["Refreshed at \(stamp)"], ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"], ["Go"]
                ])
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.append") { _, windowUUID, _, _, _ in
            let item = listExtraItems[listAppendIndex % listExtraItems.count]
            listAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [[item]])
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 1)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.selection.changed") { _, windowUUID, _, _, _ in
            let selected = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String]
            let label = selected?.first.map { "Selected: \($0)" } ?? "Selected: <none>"
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: label)
        }
        // Programmatic selection demos — selecting in code does not fire
        // list.demo.selection.changed, so each handler updates the status label itself.
        ActionUISwift.registerActionHandler(actionID: "list.demo.select.index") { _, windowUUID, _, _, _ in
            if let row = ActionUISwift.selectElementRow(windowUUID: windowUUID, viewID: 1, index: 3) {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Selected row #4 by index: \(row.joined())")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Selected: <none> — row #4 unavailable, load items first.")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.select.content") { _, windowUUID, _, _, _ in
            if let index = ActionUISwift.selectElementRow(windowUUID: windowUUID, viewID: 1, matching: "Rust") {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Matched \"Rust\" at row #\(index + 1).")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                    value: "Selected: <none> — \"Rust\" not in the list.")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "list.demo.deselect") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementSelection(windowUUID: windowUUID, viewID: 1)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Selected: <none>")
        }
        // Double-click demo: the framework routes a row double-click (and Return on a
        // selected row) through the List's primaryAction. The action context is the
        // 0-based row index; the double-clicked row is the current selection.
        ActionUISwift.registerActionHandler(actionID: "list.demo.double.click") { _, windowUUID, _, _, context in
            let index = context as? Int ?? -1
            let item = (ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 1) as? [String])?.first ?? ""
            print("Double-click action executed: list.demo.double.click — row \(index): \(item)")
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                value: "Double-clicked row \(index): \(item)")
        }

        // contextMenu demo (View.contextMenu.json): the menu items are real Buttons, so
        // each fires its OWN actionID (viewID = the Button's id). The status label (700)
        // echoes which action ran.
        let contextMenuActions: [String: String] = [
            "context.demo.rename": "Rename", "context.demo.share": "Share",
            "context.demo.delete": "Delete", "context.demo.open": "Open",
        ]
        for (actionID, label) in contextMenuActions {
            ActionUISwift.registerActionHandler(actionID: actionID) { _, windowUUID, _, _, _ in
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 700, value: "Chose \"\(label)\".")
            }
        }

        // swipeActions demo (View.swipeActions.json): each swipe Button fires its OWN
        // actionID (viewID = the Button's id). The status label (720) echoes which action
        // ran - the host would actually delete/flag/archive the row in a real app.
        let swipeActions: [String: String] = [
            "swipe.demo.flag": "Flag", "swipe.demo.delete": "Delete",
            "swipe.demo.pin": "Pin", "swipe.demo.archive": "Archive",
            "swipe.demo.read": "Mark Read",
        ]
        for (actionID, label) in swipeActions {
            ActionUISwift.registerActionHandler(actionID: actionID) { _, windowUUID, _, _, _ in
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 720, value: "Swiped \"\(label)\".")
            }
        }

        // VStack template demo handlers (VStack.template.json)
        // IDs: 10 = VStack+Label, 20 = VStack+HStack, 30 = HStack chips, 99 = status label
        let vstackTemplateRows: [[String]] = [
            ["star.fill",       "Favorites"],
            ["heart.fill",      "Liked"],
            ["clock",           "Recent"],
            ["bookmark.fill",   "Saved"],
            ["bell.fill",       "Notifications"]
        ]
        var vstackTemplateAppendIndex = 0
        let vstackTemplateExtraRows: [[String]] = [
            ["archivebox.fill", "Archive"],
            ["trash.fill",      "Trash"],
            ["folder.fill",     "Folder"]
        ]
        let vstackChipRows: [[String]] = [
            ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"]
        ]

        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 10, rows: vstackTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 20, rows: vstackTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 30, rows: vstackChipRows)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Tap a row or chip to see the action here.")
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.append") { _, windowUUID, _, _, _ in
            let row = vstackTemplateExtraRows[vstackTemplateAppendIndex % vstackTemplateExtraRows.count]
            vstackTemplateAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 10, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 20, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 30, rows: [[row[1]]])
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 10)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 20)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 30)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Cleared.")
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.select") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let row = rows[viewPartID]
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Selected row \(viewPartID): \(row.joined(separator: " / "))")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "vstack.template.demo.chip") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let chip = rows[viewPartID].first ?? "?"
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Chip tapped: \(chip) (row \(viewPartID))")
            }
        }

        // Lazy grid template demo handlers (LazyVGrid.template.json)
        // IDs: 40 = LazyVGrid+Button cells, 50 = LazyHGrid+Text cells, 99 = status label
        let gridTemplateRows: [[String]] = [
            ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"],
            ["Go"], ["C"], ["C++"], ["Ruby"]
        ]
        var gridTemplateAppendIndex = 0
        let gridTemplateExtraRows: [[String]] = [
            ["Haskell"], ["Elixir"], ["Julia"], ["Zig"], ["Dart"]
        ]

        ActionUISwift.registerActionHandler(actionID: "grid.template.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 40, rows: gridTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 50, rows: gridTemplateRows)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Tap a cell to see the action here.")
        }
        ActionUISwift.registerActionHandler(actionID: "grid.template.demo.append") { _, windowUUID, _, _, _ in
            let row = gridTemplateExtraRows[gridTemplateAppendIndex % gridTemplateExtraRows.count]
            gridTemplateAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 40, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 50, rows: [row])
        }
        ActionUISwift.registerActionHandler(actionID: "grid.template.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 40)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 50)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Cleared.")
        }
        ActionUISwift.registerActionHandler(actionID: "grid.template.demo.select") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let cell = rows[viewPartID].first ?? "?"
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Cell tapped: \(cell) (row \(viewPartID))")
            }
        }

        // List template demo handlers (List.template.json)
        // IDs: 11 = List+Label, 21 = List+HStack, 31 = List+Button, 99 = status label
        let listTemplateRows: [[String]] = [
            ["star.fill",       "Favorites"],
            ["heart.fill",      "Liked"],
            ["clock",           "Recent"],
            ["bookmark.fill",   "Saved"],
            ["bell.fill",       "Notifications"]
        ]
        var listTemplateAppendIndex = 0
        let listTemplateExtraRows: [[String]] = [
            ["archivebox.fill", "Archive"],
            ["trash.fill",      "Trash"],
            ["folder.fill",     "Folder"]
        ]
        let listChipRows: [[String]] = [
            ["Swift"], ["Python"], ["Kotlin"], ["TypeScript"], ["Rust"]
        ]

        ActionUISwift.registerActionHandler(actionID: "list.template.demo.load") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 11, rows: listTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 21, rows: listTemplateRows)
            ActionUISwift.setElementRows(windowUUID: windowUUID, viewID: 31, rows: listChipRows)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Tap a row or button to see the action here.")
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.append") { _, windowUUID, _, _, _ in
            let row = listTemplateExtraRows[listTemplateAppendIndex % listTemplateExtraRows.count]
            listTemplateAppendIndex += 1
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 11, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 21, rows: [row])
            ActionUISwift.appendElementRows(windowUUID: windowUUID, viewID: 31, rows: [[row[1]]])
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.clear") { _, windowUUID, _, _, _ in
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 11)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 21)
            ActionUISwift.clearElementRows(windowUUID: windowUUID, viewID: 31)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Cleared.")
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.select") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let row = rows[viewPartID]
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Selected row \(viewPartID): \(row.joined(separator: " / "))")
            }
        }
        ActionUISwift.registerActionHandler(actionID: "list.template.demo.chip") { _, windowUUID, viewID, viewPartID, _ in
            if let rows = ActionUISwift.getElementRows(windowUUID: windowUUID, viewID: viewID),
               rows.indices.contains(viewPartID) {
                let chip = rows[viewPartID].first ?? "?"
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99,
                    value: "Chip tapped: \(chip) (row \(viewPartID))")
            }
        }

        // Sheet demo handlers
        ActionUISwift.registerActionHandler(actionID: "sheet.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Sheet dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "cover.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Full screen cover dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.presentModal.sheet") { _, windowUUID, _, _, _ in
            guard let url = Bundle.main.url(forResource: "Sheet.modal", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }
            try? ActionUISwift.presentModal(
                windowUUID: windowUUID, data: data, format: "json",
                style: .sheet, onDismissActionID: "sheet.demo.tier2.dismissed"
            )
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.presentModal.cover") { _, windowUUID, _, _, _ in
            guard let url = Bundle.main.url(forResource: "Sheet.modal", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return }
            try? ActionUISwift.presentModal(
                windowUUID: windowUUID, data: data, format: "json",
                style: .fullScreenCover, onDismissActionID: "sheet.demo.tier2.dismissed"
            )
        }
        ActionUISwift.registerActionHandler(actionID: "sheet.demo.tier2.dismissed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Window-level modal dismissed.")
        }
        ActionUISwift.registerActionHandler(actionID: "modal.dismiss") { _, windowUUID, _, _, _ in
            ActionUISwift.dismissModal(windowUUID: windowUUID)
        }

        // Alert demo handlers
        ActionUISwift.registerActionHandler(actionID: "demo.showAlert") { _, windowUUID, _, _, _ in
            ActionUISwift.presentAlert(
                windowUUID: windowUUID,
                title: "Hello",
                message: "This is a window-level alert."
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showAlertCustom") { _, windowUUID, _, _, _ in
            let buttons: [ActionUI.DialogButton] = [
                .init(title: "Delete", role: .destructive, actionID: "demo.delete.confirmed"),
                .init(title: "Cancel", role: .cancel, actionID: nil)
            ]
            ActionUISwift.presentAlert(
                windowUUID: windowUUID,
                title: "Delete Item?",
                message: "This action cannot be undone.",
                buttons: buttons
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showConfirmation") { _, windowUUID, _, _, _ in
            let buttons: [ActionUI.DialogButton] = [
                .init(title: "Save", role: nil, actionID: "demo.save.confirmed"),
                .init(title: "Don't Save", role: .destructive, actionID: "demo.discard.confirmed"),
                .init(title: "Cancel", role: .cancel, actionID: nil)
            ]
            ActionUISwift.presentConfirmationDialog(
                windowUUID: windowUUID,
                title: "Save changes?",
                message: "Your changes will be lost if you don't save.",
                buttons: buttons
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.delete.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Deleted!")
        }
        ActionUISwift.registerActionHandler(actionID: "demo.save.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Saved!")
        }
        ActionUISwift.registerActionHandler(actionID: "demo.discard.confirmed") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Discarded.")
        }

        // Toast demo handlers
        ActionUISwift.registerActionHandler(actionID: "demo.showToast") { _, windowUUID, _, _, _ in
            ActionUISwift.presentToast(windowUUID: windowUUID, message: "All done for the day")
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showToastUndo") { _, windowUUID, _, _, _ in
            ActionUISwift.presentToast(
                windowUUID: windowUUID,
                message: "Completed evening chores",
                actionTitle: "Undo",
                actionID: "demo.toast.undo"
            )
        }
        ActionUISwift.registerActionHandler(actionID: "demo.showToastQueue") { _, windowUUID, _, _, _ in
            ActionUISwift.presentToast(windowUUID: windowUUID, message: "Morning tasks complete", duration: 2.0)
            ActionUISwift.presentToast(windowUUID: windowUUID, message: "Afternoon tasks complete", duration: 2.0)
            ActionUISwift.presentToast(windowUUID: windowUUID, message: "Evening tasks complete", duration: 2.0)
        }
        ActionUISwift.registerActionHandler(actionID: "demo.toast.undo") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Undo tapped - entry restored.")
        }

        // Searchable demo handler: the search query arrives as the action context on each change.
        ActionUISwift.registerActionHandler(actionID: "demo.search") { _, windowUUID, _, _, context in
            let query = context as? String ?? ""
            let echo = query.isEmpty ? "Query cleared." : "Query: \"\(query)\""
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: echo)
        }

        // HoverDrop demo handlers
        // IDs: 1=hover card, 2=hover status text,
        //      3=text drop zone, 4=text zone label, 5=text result panel, 6=text result content,
        //      7=file drop zone, 8=file zone label, 9=file result panel, 10=file result content

        ActionUISwift.registerActionHandler(actionID: "demo.card.hovered") { _, windowUUID, _, _, context in
            let isHovering = (context as? [String: Any])?["isHovering"] as? Bool ?? false
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2,
                value: isHovering ? "Pointer is over the card" : "Move the pointer over this card")
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 1,
                propertyName: "background",
                value: isHovering ? "fill.secondary" : "background.secondary")
        }

        ActionUISwift.registerActionHandler(actionID: "demo.drop.targeted") { _, windowUUID, _, _, context in
            let isTargeted = (context as? [String: Any])?["isTargeted"] as? Bool ?? false
            let border: [String: Any] = isTargeted
                ? ["color": "accentcolor", "width": 2.0]
                : ["color": "separator", "width": 1.0]
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 3,
                propertyName: "border", value: border)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 4,
                value: isTargeted ? "Release to drop ↓" : "Drop text here")
        }

        ActionUISwift.registerActionHandler(actionID: "demo.drop.received") { _, windowUUID, _, _, context in
            let dict = context as? [String: Any]
            let items = dict?["items"] as? [String] ?? []
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 5,
                propertyName: "hidden", value: false)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 6,
                value: items.first ?? "(no text content)")
            // Reset drop zone appearance
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 3,
                propertyName: "border", value: ["color": "separator", "width": 1.0] as [String: Any])
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 4, value: "Drop text here")
        }

        ActionUISwift.registerActionHandler(actionID: "demo.file.drop.targeted") { _, windowUUID, _, _, context in
            let isTargeted = (context as? [String: Any])?["isTargeted"] as? Bool ?? false
            let border: [String: Any] = isTargeted
                ? ["color": "accentcolor", "width": 2.0]
                : ["color": "separator", "width": 1.0]
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 7,
                propertyName: "border", value: border)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 8,
                value: isTargeted ? "Release to drop ↓" : "Drop files or folders here")
        }

        ActionUISwift.registerActionHandler(actionID: "demo.file.drop.received") { _, windowUUID, _, _, context in
            let dict = context as? [String: Any]
            let items = dict?["items"] as? [String] ?? []
            print("[HoverDrop] file drop received — items: \(items), context: \(String(describing: context))")
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 9,
                propertyName: "hidden", value: false)
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 10,
                value: items.isEmpty ? "(no items)" : items.joined(separator: "\n"))
            // Reset drop zone appearance
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 7,
                propertyName: "border", value: ["color": "separator", "width": 1.0] as [String: Any])
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 8, value: "Drop files or folders here")
        }

        // Text content type demo handlers (Text.contentType.json)
        // IDs: 1 = TextEditor (read-only display), 2 = status label
        let contentTypeRTF = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}} \\f0 {\\b Bold RTF} and {\\i italic} with {\\b\\i bold-italic} text.}"
        let contentTypeHTML = "<html><body style=\"font-family: -apple-system\"><b>Bold HTML</b> and <i><span style=\"color: #CC0000\">red italic</span></i> text.</body></html>"
        let contentTypeJSON = "[{\"text\":\"Bold JSON \",\"bold\":true},{\"text\":\"and \",\"italic\":true,\"color\":\"#0055CC\"},{\"text\":\"mixed\",\"bold\":true,\"italic\":true,\"underline\":true}]"

        ActionUISwift.registerActionHandler(actionID: "text.contenttype.set.rtf") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: contentTypeRTF, contentType: "rtf")
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Active content type: rtf")
        }
        ActionUISwift.registerActionHandler(actionID: "text.contenttype.set.html") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: contentTypeHTML, contentType: "html")
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Active content type: html")
        }
        ActionUISwift.registerActionHandler(actionID: "text.contenttype.set.json") { _, windowUUID, _, _, _ in
            ActionUISwift.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: contentTypeJSON, contentType: "json")
            ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Active content type: json")
        }
        ActionUISwift.registerActionHandler(actionID: "text.contenttype.get.json") { _, windowUUID, _, _, _ in
            if let jsonStr = ActionUISwift.getElementValueAsString(windowUUID: windowUUID, viewID: 1, contentType: "json") {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 1, value: jsonStr)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Showing raw JSON runs output")
            } else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "No attributed content to serialize")
            }
        }

        // Animation demo handlers
        // IDs: 101=circle, 102=rectangle, 103=roundedRect, 104=capsule, 105=rectangle-rotate
        var anim101Opacity = true
        var anim101Scale   = true
        var anim102Opacity = true
        var anim102Scale   = true
        var anim103Scale   = true
        let anim104Colors  = ["purple", "orange", "teal", "pink", "indigo"]
        var anim104ColorIndex = 0
        var anim105Rotation: Double = 0

        ActionUISwift.registerActionHandler(actionID: "anim.demo.101.opacity") { _, windowUUID, _, _, _ in
            anim101Opacity.toggle()
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 101,
                propertyName: "opacity", value: anim101Opacity ? 1.0 : 0.25)
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.101.scale") { _, windowUUID, _, _, _ in
            anim101Scale.toggle()
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 101,
                propertyName: "scaleEffect", value: anim101Scale ? 1.0 : 0.5)
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.102.opacity") { _, windowUUID, _, _, _ in
            anim102Opacity.toggle()
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 102,
                propertyName: "opacity", value: anim102Opacity ? 1.0 : 0.2)
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.102.scale") { _, windowUUID, _, _, _ in
            anim102Scale.toggle()
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 102,
                propertyName: "scaleEffect", value: anim102Scale ? 1.0 : 1.4)
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.103.scale") { _, windowUUID, _, _, _ in
            anim103Scale.toggle()
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 103,
                propertyName: "scaleEffect", value: anim103Scale ? 0.5 : 1.0)
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.104.color") { _, windowUUID, _, _, _ in
            anim104ColorIndex = (anim104ColorIndex + 1) % anim104Colors.count
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 104,
                propertyName: "foregroundStyle", value: anim104Colors[anim104ColorIndex])
        }
        ActionUISwift.registerActionHandler(actionID: "anim.demo.105.rotate") { _, windowUUID, _, _, _ in
            anim105Rotation += 90
            ActionUISwift.setElementProperty(windowUUID: windowUUID, viewID: 105,
                propertyName: "rotationEffect", value: anim105Rotation)
        }

        // InsertElement demo handlers (InsertElement.json)
        // IDs: 2 = Grid container, 10 = Item A, 11 = Item B, 20/21 = initial Grid cells, 99 = status label
        // Dynamically inserted grid cell pairs start at 200.

        var insertGridCounter = 200
        ActionUISwift.registerActionHandler(actionID: "insert.demo.appendRow") { _, windowUUID, _, _, _ in
            let c0 = insertGridCounter; insertGridCounter += 1
            let c1 = insertGridCounter; insertGridCounter += 1
            do {
                let rowNum = (insertGridCounter / 2) - 100
                try ActionUISwift.insertRow(
                    windowUUID: windowUUID, parentID: 2,
                    json: "[{\"id\":\(c0),\"type\":\"Text\",\"properties\":{\"text\":\"R\(rowNum) C0\",\"font\":\"caption\"}},{\"id\":\(c1),\"type\":\"Text\",\"properties\":{\"text\":\"R\(rowNum) C1\",\"font\":\"caption\"}}]"
                )
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Appended grid row (ids \(c0), \(c1))")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        ActionUISwift.registerActionHandler(actionID: "insert.demo.prependRow") { _, windowUUID, _, _, _ in
            let c0 = insertGridCounter; insertGridCounter += 1
            let c1 = insertGridCounter; insertGridCounter += 1
            do {
                let rowNum = (insertGridCounter / 2) - 100
                try ActionUISwift.insertRow(
                    windowUUID: windowUUID, parentID: 2,
                    json: "[{\"id\":\(c0),\"type\":\"Text\",\"properties\":{\"text\":\"R\(rowNum) C0\",\"font\":\"caption\"}},{\"id\":\(c1),\"type\":\"Text\",\"properties\":{\"text\":\"R\(rowNum) C1\",\"font\":\"caption\"}}]",
                    position: .prepend
                )
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Prepended grid row (ids \(c0), \(c1))")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        // List.insertElement demo handlers (List.insertElement.json)
        // IDs: 1 = List container, 10 = Item A, 11 = Item B, 99 = status label
        // Inserts Label elements with cycling SF Symbols.
        let listInsertSymbols = ["star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "drop.fill", "moon.fill", "sun.max.fill"]
        var listInsertCounter = 100
        var listInsertedIDs: [Int] = []

        ActionUISwift.registerActionHandler(actionID: "list.insert.demo.append") { _, windowUUID, _, _, _ in
            let id = listInsertCounter; listInsertCounter += 1
            let sym = listInsertSymbols[id % listInsertSymbols.count]
            do {
                try ActionUISwift.insertElement(
                    windowUUID: windowUUID, parentID: 1,
                    json: #"{"id":\#(id),"type":"Label","properties":{"title":"Appended (id: \#(id))","systemImage":"\#(sym)"}}"#
                )
                listInsertedIDs.append(id)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Appended label id \(id)")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        ActionUISwift.registerActionHandler(actionID: "list.insert.demo.prepend") { _, windowUUID, _, _, _ in
            let id = listInsertCounter; listInsertCounter += 1
            let sym = listInsertSymbols[id % listInsertSymbols.count]
            do {
                try ActionUISwift.insertElement(
                    windowUUID: windowUUID, parentID: 1,
                    json: #"{"id":\#(id),"type":"Label","properties":{"title":"Prepended (id: \#(id))","systemImage":"\#(sym)"}}"#,
                    position: .prepend
                )
                listInsertedIDs.append(id)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Prepended label id \(id)")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        ActionUISwift.registerActionHandler(actionID: "list.insert.demo.afterA") { _, windowUUID, _, _, _ in
            let id = listInsertCounter; listInsertCounter += 1
            let sym = listInsertSymbols[id % listInsertSymbols.count]
            do {
                try ActionUISwift.insertElement(
                    windowUUID: windowUUID, parentID: 1,
                    json: #"{"id":\#(id),"type":"Label","properties":{"title":"After A (id: \#(id))","systemImage":"\#(sym)"}}"#,
                    position: .after(siblingID: 10)
                )
                listInsertedIDs.append(id)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Inserted after A, label id \(id)")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        ActionUISwift.registerActionHandler(actionID: "list.insert.demo.removeLast") { _, windowUUID, _, _, _ in
            guard let id = listInsertedIDs.popLast() else {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Nothing to remove.")
                return
            }
            do {
                try ActionUISwift.removeElement(windowUUID: windowUUID, viewID: id)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Removed label id \(id)")
            } catch {
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 99, value: "Error: \(error)")
            }
        }

        // LazyVStack.insertElement chat demo handlers (LazyVStack.insertElement.json)
        // IDs: 1 = LazyVStack container, 2 = TextField input
        // Inserts a right-aligned chat bubble (HStack + Spacer + Text) for each sent message.
        ActionUISwift.registerActionHandler(actionID: "chat.demo.send") { _, windowUUID, _, _, _ in
            guard let text = ActionUISwift.getElementValue(windowUUID: windowUUID, viewID: 2) as? String,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let bubbleDict: [String: Any] = [
                "type": "HStack",
                "children": [
                    ["type": "Spacer"] as [String: Any],
                    ["type": "Text", "properties": [
                        "text": text,
                        "foregroundStyle": "white",
                        "padding": "default",
                        "background": "blue",
                        "clipShape": ["type": "roundedRectangle", "cornerRadius": 12] as [String: Any],
                        "frame": ["maxWidth": 260]
                    ] as [String: Any]] as [String: Any]
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: bubbleDict),
                  let json = String(data: data, encoding: .utf8) else { return }
            do {
                try ActionUISwift.insertElement(windowUUID: windowUUID, parentID: 1, json: json)
                ActionUISwift.setElementValue(windowUUID: windowUUID, viewID: 2, value: "")
            } catch {
                print("[chat.demo.send] Error: \(error)")
            }
        }

        if shouldResetState {
            // Clear custom state
            UserDefaults.standard.removeObject(forKey: "openWindows")
        }
    }
    
    var body: some Scene {
        WindowGroup("JSON Selector") {
            NavigationStack {
                JSONSelectorView(logger: logger)
                    .onAppear {
                        if shouldResetState && supportsMultipleWindows {
                            // Ensure JSON Selector window is open
                            openWindow(id: "JSON Selector")
                            // Log open windows/sessions for debugging
                            #if canImport(UIKit)
                            print("Open sessions: \(UIApplication.shared.openSessions.map { $0.persistentIdentifier })")
                            #endif
                            #if canImport(AppKit)
                            print("Open windows: \(NSApplication.shared.windows.map { $0.title })")
                            #endif
                        }
                    }
            }
        }
        .handlesExternalEvents(matching: ["JSON Selector"])
        
        WindowGroup(for: WindowIdentifier.self) { $windowIdentifier in
            if supportsMultipleWindows, let identifier = windowIdentifier, !shouldResetState {
                if let url = Bundle.main.url(forResource: identifier.resourceName, withExtension: ".json") {
                    AnyView(ActionUISwift.loadView(from: url, windowUUID: identifier.windowUUID, isContentView: true))
                }
            } else {
                EmptyView()
            }
        }
        .handlesExternalEvents(matching: ["ActionUIContent-*"])
        .commands {
            SidebarCommands()
        }
        
        LoadableWindowGroup.load(
            fromResource: "DefaultWindow",
            windowUUID: UUID().uuidString,
            logger: logger
        )
        .handlesExternalEvents(matching: ["DefaultWindow"])
        // TODO: looks like CommandGroup & CommandMenu buttons with shortcuts will require special handling
        // this example command shortcut works but the ones set in base View.applyModifiers do not appear:
        .commands {
            
            TextEditingCommands()
            
            CommandGroup(after: .help) {
                Button("Help from ActionUISwiftTestApp") {
                    // Action for the About command
                    print("Help from ActionUISwiftTestApp triggered")
                }
                .keyboardShortcut("H", modifiers: [.command, .shift]) // Add a keyboard shortcut
            }
        }
    }
}

struct WindowIdentifier: Hashable, Codable {
    let resourceName: String
    let windowUUID: String
    
    enum CodingKeys: String, CodingKey {
        case resourceName
        case windowUUID
    }
    
    init(resourceName: String, windowUUID: String) {
        self.resourceName = resourceName
        self.windowUUID = windowUUID
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceName = try container.decode(String.self, forKey: .resourceName)
        windowUUID = try container.decode(String.self, forKey: .windowUUID)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resourceName, forKey: .resourceName)
        try container.encode(windowUUID, forKey: .windowUUID)
    }
}

struct JSONSelectorView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var selectedResource: String?
    let logger: any ActionUILogger

    private var supportsMultipleWindows: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsMultipleScenes
        #else
        return true // macOS supports multiple windows
        #endif
    }

    // Compute jsonFiles outside view builder
    private var jsonFiles: [String] {
        Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
            .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
            .filter { $0 != "DefaultWindow" } // Filter out DefaultWindow to avoid duplication
    }

    var body: some View {
        if jsonFiles.isEmpty {
            Text("No JSON files found in the app bundle.")
                .padding()
                .accessibilityIdentifier("no_json_files_text")
        } else {
            if supportsMultipleWindows {
                List {
                    Button("Default Window") {
                        openWindow(id: "WelcomeWindow") // WelcomeWindow is the windowGroupID declared in JSON description
                    }
                    .accessibilityIdentifier("default_window_button")

                    ForEach(jsonFiles, id: \.self) { name in
                        Button(name) {
                            let windowUUID = UUID().uuidString
                            openWindow(value: WindowIdentifier(resourceName: name, windowUUID: windowUUID))
                        }
                    }
                }
                .navigationTitle("JSON Selector")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("json_selector_list")
            }
            else {
            #if canImport(UIKit)
            
                // Single-window mode (iOS without multi-scene support):
                // use fullScreenCover to avoid nesting NavigationStacks.
                // JSON views like NavigationStack.json create their own NavigationStack,
                // so embedding them inside the outer NavigationStack causes broken navigation on iOS.
                List(jsonFiles, id: \.self) { name in
                    Button(name) {
                        selectedResource = name
                    }
                }
                .navigationTitle("JSON Selector")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("json_selector_list")
                // Test hook: `-openResource <Name>` opens that document's fullScreenCover on launch,
                // so a document can be screenshotted edge-to-edge without GUI navigation.
                .onAppear {
                    if let idx = CommandLine.arguments.firstIndex(of: "-openResource"),
                       idx + 1 < CommandLine.arguments.count {
                        selectedResource = CommandLine.arguments[idx + 1]
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { selectedResource != nil },
                    set: { if !$0 { selectedResource = nil } }
                )) {
                    GeometryReader { _ in
                        if let resourceName = selectedResource,
                           let url = Bundle.main.url(forResource: resourceName, withExtension: ".json") {
                            AnyView(ActionUISwift.loadView(from: url, windowUUID: resourceName, isContentView: true))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            selectedResource = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                }
            #endif // canImport(UIKit)
            }
        }
    }
}

#Preview {
    NavigationStack {
        JSONSelectorView(logger: ConsoleLogger(maxLevel: .verbose))
    }
}
