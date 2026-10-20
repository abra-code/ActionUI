// Core/Elements/List.swift
/*
  Sample JSON for List view:
  {
    "type": "List",
    "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
    "properties": {
      // Form 1: Homogeneous list of pre-declared types from external data
      "itemType": {                            // Optional: Defaults to { "viewType": "Text" }
        "viewType": "Button",                  // "Text"|"Button"|"Image"|"AsyncImage"
        "actionContext": "rowIndex",           // "title"|"rowIndex" (Button only)
        "actionID": "list.buttonClick",        // Button only — fires on button click
        "dataInterpretation": "systemName"     // "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
      },
      "actionID": "list.selection.changed",    // Optional: Fires on every selection change the user makes, a deselect included (all cell types)
      "doubleClickActionID": "list.double.click",  // Optional: String for double-click action (macOS only, context = row index)
      "onRefreshActionID": "list.refresh",      // Optional: String. When set, enables pull-to-refresh; fires this actionID on pull. The spinner stays until the client delivers fresh data to this list or anything inside it (any setElementRows/appendElementRows/clearElementRows/setElementValue/setElementState call targeting this list or a descendant), or a safety timeout elapses.
      // List styling
      "listStyle": "plain",                   // Optional: list style — platform availability below
                                              //   "automatic"    — all platforms (system default)
                                              //   "plain"        — all platforms
                                              //   "inset"        — iOS, macOS, visionOS
                                              //   "sidebar"      — iOS, macOS, visionOS
                                              //   "grouped"      — iOS, tvOS, visionOS
                                              //   "insetGrouped" — iOS, visionOS only
      // Row styling — applied uniformly to all rows
      "listRowBackground": "blue",            // Optional: Color string (e.g., "blue", "#FF0000") — all platforms
      "listRowSeparator": "hidden",           // Optional: "visible"|"hidden"|"automatic" — iOS/macOS/visionOS only
      "listRowSeparatorTint": "gray",         // Optional: Color string for separator tint — iOS/macOS/visionOS only
      "listRowInsets": 16,                    // Optional: Number for uniform insets or {"top": 8, "leading": 16, "bottom": 8, "trailing": 16}
    },
    // Form 2: Heterogeneous list from embedded JSON
    "children": [                            // Optional: Array of child views for complex lists
      {
        "type": "NavigationLink",
        "id": 10,                            // Recommended: Set unique ID for selection support
        "properties": {
          "title": "Item 1"
        },
        "destination": {                   // Destination must be a full view element
          "type": "Text",
          "properties": { "title": "Item 1 Detail" }
        }
      },
      {
        "type": "Button",
        "id": 11,                            // Recommended: Set unique ID for selection support
        "properties": { "title": "Item 2" }
      }
    ],
    // Form 3: Data-driven list with template (replaces itemType with full ActionUI template)
    "template": {                           // "template" presence activates data-driven template mode; "id" required
      "type": "HStack",
      "children": [
        { "type": "Image", "properties": { "systemName": "$1" } }, // $1, $2, etc. are 1-based data column indexes
        { "type": "Text",  "properties": { "text": "$2" } }
      ]
    }
    // A checkbox list is a template with a Toggle: the row holds the state, a user toggle writes
    // it back into the row and fires the Toggle's actionID with the row index (see Toggle.swift):
    //   "template": { "type": "Toggle", "properties": { "style": "checkbox", "isOn": "$1", "title": "$2", "actionID": "item.toggled" } }
  }
    // Note: The List can operate in three modes (Form 1, 2, and 3):
    //   1. Homogeneous list: Shows a single-column list of homogeneous views (Text, Button, Image, AsyncImage)
    //      specified by itemType.viewType. Selection is stored as [String] in state, using the item string or id.
    //      The list-level actionID fires on selection change. Button items have their own actionID in itemType,
    //      fired on click — this cleanly separates selection events from button click events. On macOS,
    //      double-click triggers doubleClickActionID with row index as context.
    //   2. Heterogeneous list: Shows a list of arbitrary views defined in the "children" array.
    //      Operates in two sub-modes depending on whether actionID is set:
    //
    //      a) With actionID (selectable mode): List(selection:) binding is enabled using
    //         bidirectional child-ID mapping (same pattern as NavigationSplitView.buildSidebarList).
    //         Selection is stored in model.value as [String] with the stringified child element ID.
    //         actionID fires on selection change. Children should be Labels/Text (not NavigationLinks)
    //         because List(selection:) intercepts taps on iOS.
    //         When used inside NavigationStack with destinations, NavigationStack detects this pattern
    //         and handles push navigation — see NavigationStack.swift.
    //         Row styling (listRowBackground/listRowSeparator/listRowInsets) is applied via
    //         a rowModifier closure passed to SelectionListHelper.buildSelectableList.
    //
    //      b) Without actionID (no-selection mode): No selection binding. NavigationLinks handle
    //         their own taps. Action callbacks:
    //           - Button children: fire their own actionID on tap.
    //           - NavigationLink children: push destinations via NavigationStack.
    //           - Label/Text children: display-only; use Button if tap action is needed.
    //         Row styling properties are applied to each child view.
    //
    //      Note: NavigationSplitView sidebar selection is handled by NavigationSplitView.buildSidebarList(),
    //      which constructs its own List(selection:) — it does not go through this List.buildView path.
    //      Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
    //      cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and
    //      applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
    //   3. Template-based list: homogeneous rows of ActionUI views based on pre-declared template
    //      Column text values are assigned to specific sub-view values by index
    //      Column indexes are 1-based: $1 (col 0), $2 (col 1), $N (col N-1), $0 (all)
    //      Data set via setElementRows/appendElementRows/clearElementRows.
    //      Selection and doubleClickActionID work the same as Form 1.
    //
    //    Performance: Rows are identified by stable indices in ForEach, optimizing SwiftUI diffing for
    //    large lists (e.g., 10,000 items). When row styling properties (listRowBackground, listRowSeparator,
    //    listRowInsets) are set, rows are wrapped with AnyView to support modifier chaining. Without row
    //    styling, this is a no-op wrapper with negligible overhead. Image creation uses SwiftUI.Image
    //    extension, aligned with Image.swift. Ensure state updates are targeted to minimize re-renders.

  Observable state:
    value ([String])                   Selected item as a one-element string array (or empty when nothing selected).
                                       Access via getElementValue / setElementValue. Select a row
                                       programmatically (without replacing rows, firing no actionID) via
                                       selectElementRow(index:), selectElementRow(matching:column:), or
                                       clearElementSelection (content-backed list modes only — not
                                       heterogeneous children, which select by child element ID).
    states["content"]  [[String]]      All list items; each inner array holds the item string and any optional
                                       hidden-column data. Access via getElementRows / setElementRows /
                                       appendElementRows / clearElementRows.
                                       A rows change keeps the selection on its row (an equal row, else the row with
                                       the same first column, the same one among several, with its new columns), or
                                       clears it; no actionID fires.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension List {
    /// List's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The cell of a homogeneous list (itemType.viewType). "Toggle" and unknown names are Text.
        enum ViewType: String, Sendable, CaseIterable {
            case text = "Text", button = "Button", image = "Image", asyncImage = "AsyncImage"
        }

        /// How an Image cell reads its row text (itemType.dataInterpretation).
        enum DataInterpretation: String, Sendable, CaseIterable {
            case path, systemName, assetName, resourceName, mixed
        }

        /// What a Button cell passes as its action's context (itemType.actionContext).
        enum ActionContext: String, Sendable, CaseIterable {
            case title, rowIndex
        }

        /// Not every style exists on every platform; the renderer applies none for a missing one.
        enum ListStyle: String, Sendable, CaseIterable {
            case automatic, plain, inset, sidebar, grouped, insetGrouped
        }

        enum RowSeparator: String, Sendable, CaseIterable {
            case visible, hidden, automatic
        }

        enum RowInsets: Equatable, Sendable {
            case uniform(Double)
            /// Missing edges are 0.
            case edges(top: Double, leading: Double, bottom: Double, trailing: Double)
        }

        var viewType = ViewType.text
        var dataInterpretation = DataInterpretation.systemName
        var actionContext = ActionContext.title
        /// itemType.actionID: the action of a Button cell.
        var itemActionID: String?
        /// Fires on every selection change the user makes.
        var actionID: String?
        var doubleClickActionID: String?
        var onRefreshActionID: String?
        var listStyle: ListStyle?
        var rowBackground: String?
        var rowSeparator: RowSeparator?
        var rowSeparatorTint: String?
        var rowInsets: RowInsets?

        init(_ properties: [String: Any]) {
            let itemType = properties["itemType"] as? [String: Any] ?? [:]
            viewType = (itemType["viewType"] as? String).flatMap(ViewType.init(rawValue:)) ?? .text
            dataInterpretation = (itemType["dataInterpretation"] as? String).flatMap(DataInterpretation.init(rawValue:)) ?? .systemName
            actionContext = (itemType["actionContext"] as? String).flatMap(ActionContext.init(rawValue:)) ?? .title
            itemActionID = itemType["actionID"] as? String
            actionID = properties["actionID"] as? String
            doubleClickActionID = properties["doubleClickActionID"] as? String
            onRefreshActionID = properties["onRefreshActionID"] as? String
            listStyle = (properties["listStyle"] as? String).flatMap(ListStyle.init(rawValue:))
            rowBackground = properties["listRowBackground"] as? String
            rowSeparator = (properties["listRowSeparator"] as? String).flatMap(RowSeparator.init(rawValue:))
            rowSeparatorTint = properties["listRowSeparatorTint"] as? String
            // A number (Int or Double only) or a dictionary of edges.
            if let n = properties["listRowInsets"] as? Int {
                rowInsets = .uniform(Double(n))
            } else if let n = properties["listRowInsets"] as? Double {
                rowInsets = .uniform(n)
            } else if let dict = properties["listRowInsets"] as? [String: Any] {
                rowInsets = .edges(
                    top: dict.double(forKey: "top") ?? 0,
                    leading: dict.double(forKey: "leading") ?? 0,
                    bottom: dict.double(forKey: "bottom") ?? 0,
                    trailing: dict.double(forKey: "trailing") ?? 0
                )
            }
        }

        /// True when any row-level styling is set, so rows need the row modifiers.
        var hasRowModifiers: Bool {
            rowBackground != nil || rowSeparator != nil || rowSeparatorTint != nil || rowInsets != nil
        }
    }
}

struct List: ActionUIElementSpec {
    static var valueType: Any.Type = [String].self // Value is the selected item as [String]
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]

    /// The content rows a homogeneous list shows: its cell is the row's first column, and a row
    /// whose first column is empty is not shown. Returns indices into content (not positions
    /// among the shown rows), so a row's selection tag names the right content row.
    static func shownRowIndices(_ items: [[String]]) -> [Int] {
        items.indices.filter { !(items[$0].first ?? "").isEmpty }
    }

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states: [String: Any] = model.states
        if states.isEmpty {
            states["content"] = [] as [[String]]
        }
        return states
    }
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
