// SwiftUI rendering of ScrollViewReader; its portable part is in Core/Elements/ScrollViewReader.swift.
/*
 The reader scrolls the ScrollViews inside it so the element whose id is `scrollTo` shows at
 `anchor` (top, center or bottom; centered horizontally): when the reader appears (also when its
 content appears again: a tab or sheet returning), and again, animated, after every write to the
 reader (setElementProperty, setElementValue, setElementState: keyed by its view model's
 mutationToken), so writing the same scrollTo again brings the element back after the user
 scrolled away, as on Android and the web.

 SwiftUI's ScrollViewProxy finds a view by its SwiftUI identity, so inside a reader each
 ActionUIView takes its element's id as its identity (ScrollTargetIdentity, applied by
 ActionUIRegistry.applyViewModifiers); outside one, views keep their default identity.
*/

import SwiftUI

extension ScrollViewReader: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let props = Props(properties)

        return SwiftUI.ScrollViewReader { proxy in
            SwiftUI.Group {
                if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                   let childModel = windowModel.viewModels[content.id] {
                    ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
                }
            }
            .environment(\.actionUIScrollTargets, true)
            .onAppear {
                scroll(proxy, to: props.scrollTo, anchor: props.anchor)
            }
            .onChange(of: ScrollRequest(target: props.scrollTo, anchor: props.anchor, write: model.mutationToken)) { _, request in
                withAnimation(scrollAnimation) {
                    scroll(proxy, to: request.target, anchor: request.anchor)
                }
            }
        }
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        view
    }

    /// How a scroll after a write moves (the first one, on appear, jumps). Tests set nil: an XCTest
    /// window runs no animations, so an animated scroll never arrives there (measured with plain
    /// SwiftUI too).
    nonisolated(unsafe) static var scrollAnimation: Animation? = .default

    /// What a scroll is keyed by: a write to the reader with the same target scrolls again.
    private struct ScrollRequest: Equatable {
        let target: Int?
        let anchor: Props.Anchor
        let write: Int
    }

    private static func scroll(_ proxy: ScrollViewProxy, to target: Int?, anchor: Props.Anchor) {
        guard let target else { return }
        switch anchor {
        case .top: proxy.scrollTo(target, anchor: .top)
        case .center: proxy.scrollTo(target, anchor: .center)
        case .bottom: proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

/// Inside a ScrollViewReader, an element's id as its view's SwiftUI identity, which the reader's
/// ScrollViewProxy finds it by. Outside one, the view keeps its default identity.
struct ScrollTargetIdentity: ViewModifier {
    let id: Int
    @Environment(\.actionUIScrollTargets) private var isScrollTarget

    func body(content: Content) -> some SwiftUI.View {
        if isScrollTarget {
            content.id(id)
        } else {
            content
        }
    }
}

private struct ScrollTargetsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a ScrollViewReader: its descendants take their element ids as identities.
    var actionUIScrollTargets: Bool {
        get { self[ScrollTargetsKey.self] }
        set { self[ScrollTargetsKey.self] = newValue }
    }
}
