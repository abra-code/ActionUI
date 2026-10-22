// Sources/Elements/VStack+Adwaita.swift
/*
 VStack on GTK: a container laid out by StackLayout along the vertical axis.
*/

import CAdwaita

extension VStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StackLayout.makeStack(axis: .vertical)
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        StackLayout.configure(widget, spacing: props.spacing, alignment: stackAlignment(props.alignment))
        syncContainerChildren(node, widget, node.subviews("children"))
    }

    static func stackAlignment(_ alignment: Props.Alignment) -> StackSolver.Alignment {
        switch alignment {
        case .leading: return .start
        case .center: return .center
        case .trailing: return .end
        }
    }
}
