// Sources/Elements/RoundedRectangle+Adwaita.swift
/*
 RoundedRectangle on GTK: a ShapeWidget drawing the outline with the fill, else the stroke, else the
 foreground color. A continuous cornerStyle is drawn circular (ShapeWidget).
*/

import CAdwaita

extension RoundedRectangle: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        ShapeWidget.make()
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeWidget.update(widget, outline: .roundedRectangle(radius: props.cornerRadius), fill: props.fill,
                           stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }

    static var defaultExpansion: Expansion { .both }
}
