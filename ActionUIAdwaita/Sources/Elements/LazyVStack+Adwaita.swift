// Sources/Elements/LazyVStack+Adwaita.swift
/*
 LazyVStack on GTK: laid out by StackLayout as a VStack, but as measured on macOS 27 it is as wide
 as all it is offered, its children aligned in that width, and it does not expand vertically, each
 child taking its natural height (StackLayout.setLazy). Its children are all made at once, not as
 they scroll into view.
*/

import CAdwaita

extension LazyVStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = StackLayout.makeStack(axis: .vertical)
        StackLayout.setLazy(widget)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        StackLayout.configure(widget, spacing: props.spacing, alignment: stackAlignment(props.alignment))
        syncContainerContent(node, widget)
    }

    static func stackAlignment(_ alignment: Props.Alignment) -> StackSolver.Alignment {
        switch alignment {
        case .leading: return .start
        case .center: return .center
        case .trailing: return .end
        }
    }
}
