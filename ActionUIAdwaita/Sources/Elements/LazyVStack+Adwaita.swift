// Sources/Elements/LazyVStack+Adwaita.swift
/*
 LazyVStack on GTK: laid out by StackLayout as a VStack, but as measured on macOS 27 it is as wide
 as all it is offered, its children aligned in that width, and it does not expand vertically, each
 child taking its natural height (StackLayout.setLazy). Its children are all made at once; its
 template form (one instance per content row) makes a row only when it comes in or near the part
 its ScrollView shows (LazyRows).
*/

import CAdwaita

extension LazyVStack: ActionUIAdwaitaRenderer {
    /// 1 for the template form (LazyRows), 0 for the children form.
    static func widgetKind(_ node: RenderNode) -> Int {
        LazyRows.showsTemplate(node) ? 1 : 0
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        if node.widgetKind == 1 {
            return LazyRows.makeWidget(node, axis: .vertical)
        }
        let widget = StackLayout.makeStack(axis: .vertical)
        StackLayout.setLazy(widget)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        if let rows = attached(on: widget, key: lazyRowsKey) {
            rows.update(node, spacing: props.spacing, alignment: stackAlignment(props.alignment))
            return
        }
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
