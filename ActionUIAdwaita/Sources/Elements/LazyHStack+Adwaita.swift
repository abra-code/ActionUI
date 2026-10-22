// Sources/Elements/LazyHStack+Adwaita.swift
/*
 LazyHStack on GTK: laid out as an HStack. Its children are all made at once, not as they scroll
 into view.
*/

import CAdwaita

extension LazyHStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StackLayout.makeStack(axis: .horizontal)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        StackLayout.configure(widget, spacing: props.spacing, alignment: stackAlignment(props.alignment))
        syncContainerChildren(node, widget, node.subviews("children"))
    }

    static func stackAlignment(_ alignment: Props.Alignment) -> StackSolver.Alignment {
        switch alignment {
        case .top: return .start
        case .center: return .center
        case .bottom: return .end
        }
    }
}
