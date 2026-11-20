// Sources/Elements/LazyHStack+Adwaita.swift
/*
 LazyHStack on GTK: laid out by StackLayout as an HStack, but as measured on macOS 27 it is as tall
 as all it is offered (beside a Spacer in a VStack it takes all but the Spacer's minimum), its
 children aligned in that height, and it does not expand horizontally, each child taking its
 natural width (StackLayout.setLazy). Its children are all made at once, not as they scroll into
 view.
*/

import CAdwaita

extension LazyHStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget = StackLayout.makeStack(axis: .horizontal)
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
        case .top: return .start
        case .center: return .center
        case .bottom: return .end
        }
    }
}
