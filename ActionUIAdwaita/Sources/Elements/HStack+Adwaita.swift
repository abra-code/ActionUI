// Sources/Elements/HStack+Adwaita.swift
/*
 HStack on GTK: a container laid out by StackLayout along the horizontal axis. Without a spacing,
 it uses SwiftUI's default: 8 between controls, none next to a Spacer.
*/

import CAdwaita

extension HStack: ActionUIAdwaitaRenderer {
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
        // Centered until the stack aligns text baselines.
        case .firstTextBaseline, .lastTextBaseline: return .center
        }
    }
}
