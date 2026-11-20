// Sources/Elements/LazyHStack+Adwaita.swift
/*
 LazyHStack on GTK: laid out by StackLayout as an HStack, but as measured on macOS 27 it is as tall
 as all it is offered (beside a Spacer in a VStack it takes all but the Spacer's minimum), its
 children aligned in that height, and it does not expand horizontally, each child taking its
 natural width (StackLayout.setLazy). Its children are all made at once; its template form (one
 instance per content row) makes a column only when it comes in or near the part its ScrollView
 shows (LazyRows).
*/

import CAdwaita

extension LazyHStack: ActionUIAdwaitaRenderer {
    /// 1 for the template form (LazyRows), 0 for the children form.
    static func widgetKind(_ node: RenderNode) -> Int {
        LazyRows.showsTemplate(node) ? 1 : 0
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        if node.widgetKind == 1 {
            return LazyRows.makeWidget(node, axis: .horizontal)
        }
        let widget = StackLayout.makeStack(axis: .horizontal)
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
        case .top: return .start
        case .center: return .center
        case .bottom: return .end
        }
    }
}
