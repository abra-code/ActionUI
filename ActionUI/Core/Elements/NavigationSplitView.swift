// Core/Elements/NavigationSplitView.swift
/*
 Sample JSON for NavigationSplitView:

// Form 1: Static panes (no destination switching)
 {
   "type": "NavigationSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "sidebar": {          // Required: Single child view for sidebar. Note: Declared as a top-level key in JSON but stored in subviews["sidebar"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "content": {          // Optional: Single child view for content (3-pane). Note: Declared as a top-level key in JSON but stored in subviews["content"].
     "type": "Text", "properties": { "text": "Content" }
   },
   "detail": {           // Required: Single child view for detail. Note: Declared as a top-level key in JSON but stored in subviews["detail"].
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "columnVisibility": "all", // Optional: "automatic", "all", "doubleColumn", "detail"; defaults to "all"
     "style": "balanced" // Optional: "automatic", "balanced", "prominentDetail"; defaults to "automatic"
   }
 }

// Form 2: Selection-driven destination switching (2-pane)
// The sidebar must be a List whose children have a "destinationViewId" property
// linking them to destination views by id. All element ids must be unique.
// Selecting a child in the sidebar shows the corresponding destination in the detail pane.
 {
   "type": "NavigationSplitView",
   "id": 1,
   "sidebar": {
     "type": "List",
     "id": 2,
     "properties": { "actionID": "sidebar.selection.changed" },
     "children": [
       { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
       { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
     ]
   },
   "detail": {
     "type": "Text", "properties": { "text": "Select an item" }
   },
   "destinations": [
     { "type": "VStack", "id": 10, "children": [ ... ] },
     { "type": "VStack", "id": 11, "children": [ ... ] }
   ]
 }
 // Note: Sidebar children link to destinations via "destinationViewId" in properties.
 // NavigationLink is NOT needed in the sidebar for NavigationSplitView.
 // Use NavigationLink only inside NavigationStack for push-based navigation.

// Persistent toolbar: items that stay in the bar wherever the user navigates inside the split
// view, rather than only on the column that declares them. Same ToolbarItem / ToolbarItemGroup
// shapes as the per-screen "toolbar" key, and they compose with it.
 {
   "type": "NavigationSplitView",
   "id": 1,
   "persistentToolbar": [
     { "type": "ToolbarItem", "id": 16, "properties": { "placement": "primaryAction" },
       "content": { "type": "Image", "id": 17, "properties": { "systemName": "arrow.clockwise" } } }
   ],
   "sidebar": { ... },
   "detail": { ... }
 }
 // A "toolbar" declared on the NavigationSplitView itself is a DEPRECATED ALIAS for
 // "persistentToolbar"; it still works and logs a one-time warning.
 // Where the items land is per platform: macOS puts them in the shared window toolbar; platforms
 // whose columns each own a bar put them on the detail column, and on the leading columns only in
 // compact width, where the split view collapses into one stack rooted at the sidebar. A column
 // that is ITSELF a NavigationStack is the exception - there the items go onto that stack's own
 // screens, since a toolbar applied around a stack does not reach the bars inside it.
 // Implemented on Apple platforms only so far: Android and web currently ignore the key.

 // Browser back/forward (WEB ONLY, opt-in): "browserHistory:web" (Boolean, default false).
 // When true a user sidebar SELECTION adds a browser-history entry, so the browser's Back
 // button returns to the previously selected destination; a popstate restores
 // states["selectedDestination"] without re-firing the selection actionID. Off by default,
 // so Back keeps its page behavior unless the author opts in. Programmatic selection
 // (writing states["selectedDestination"]) syncs the current entry instead of adding a
 // Back target. Apple and Android ignore the key.
 //   "properties": { "browserHistory:web": true }

 // Note: These properties are specific to NavigationSplitView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).

// Observable state (via getElementState / setElementState):
//   states["columnVisibility"]     String  Current column visibility: "automatic", "all", "doubleColumn", or
//                                          "detail". Updated on user interaction; write to change programmatically.
//   states["selectedDestination"]  Int?    Currently selected destination ID (matches a destination element's id).
//                                          nil when no destination is selected. Write to change programmatically.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension NavigationSplitView {
    /// NavigationSplitView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum ColumnVisibility: String, Sendable, CaseIterable {
            case automatic, all, doubleColumn, detail
        }

        enum Style: String, Sendable, CaseIterable {
            case automatic, balanced, prominentDetail
        }

        /// A name that is not one of the four is "all"; no string at all is nil.
        var columnVisibility: ColumnVisibility?
        /// A name that is not one of the three is "automatic"; no string at all is nil.
        var style: Style?
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            if let name = properties["columnVisibility"] as? String {
                columnVisibility = ColumnVisibility(rawValue: name) ?? .all
            }
            if let name = properties["style"] as? String {
                style = Style(rawValue: name) ?? .automatic
            }
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }
}

struct NavigationSplitView: ActionUIElementSpec {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    // states["columnVisibility"] starts from the "columnVisibility" property ("all" when absent or not
    // one of the four names), unless the states already carry it.
    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states["columnVisibility"] == nil {
            states["columnVisibility"] = (Props(model.properties).columnVisibility ?? .all).rawValue
        }
        return states
    }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
}
