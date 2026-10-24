// Sources/Elements/VStack+Adwaita.swift
/*
 VStack on GTK: a container laid out by StackLayout along the vertical axis. It shows its children, or
 one template instance per content row (setElementRows; the template with the row's data, as on
 Apple; syncContainerContent).
*/

import CAdwaita

extension VStack: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        StackLayout.makeStack(axis: .vertical)
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
