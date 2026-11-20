// Sources/Elements/NavigationLink+WinUI.swift
/*
 NavigationLink on WinUI: a Button showing its title, as macOS draws a link outside a List as a
 bordered button (measured on macOS 27). A click (pointer, keyboard, or an accessibility tool's
 invoke) pushes on the enclosing NavigationStack (NavigationStack+WinUI.swift):
 - an inline "destination" view, which is not in the stack's path, as SwiftUI's view-destination
   link is not;
 - else the destination destinationViewId names in the stack's "destinations", added to the path.
 A link with neither does nothing; a click outside a NavigationStack is logged.

 Not yet: a link in a List row (macOS shows the row with a chevron; here it is a button in the row);
 a NavigationSplitView's sidebar link; dimming a link that leads nowhere, as Linux does (RenderNode
 enables the button after the update, so the renderer cannot keep it disabled).
*/

import CWinUI

/// The title a NavigationLink's button shows, kept in its node's state.
@MainActor final class NavigationLinkState {
    var title: String?
}

extension NavigationLink: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else {
            throw WinUIError.last("creating a NavigationLink")
        }
        WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a NavigationLink's click") { [weak node] in
            guard let node, node.isAttached else { return }
            let destination = node.effectiveElement.subviews?["destination"] as? any ActionUIElementBase
            let destinationID = destination == nil ? initialValue(node.model) as? Int : nil
            guard destination != nil || destinationID != nil else { return }
            NavigationStack.push(from: node, element: destination, destinationID: destinationID)
        }
        node.state = NavigationLinkState()
        return button
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        node.applyTextAppearance(to: view, what: "a NavigationLink")
        guard let state = node.state as? NavigationLinkState else { return }
        let title = Props(node.properties).title
        if state.title != title {
            if actionUIWinUIButtonSetTitle(view.pointer, title) {
                state.title = title
            } else {
                ActionUIModel.shared.logger.log("NavigationLink: \(WinUIError.last("showing the title"))", .error)
            }
        }
    }
}
