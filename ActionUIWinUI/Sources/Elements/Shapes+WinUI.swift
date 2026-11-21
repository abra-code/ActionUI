// Sources/Elements/Shapes+WinUI.swift
/*
 Color and the shapes on WinUI, as on Linux: greedy in both axes, with SwiftUI's ideal size of
 10 x 10 (FillLayout).

 - Color: the panel's background, the value (a ColorSpec set at run time) over the color property.
 - Rectangle, RoundedRectangle (cornerRadius, at most half the shorter side), Ellipse, Circle (the
   largest circle in its frame), Capsule (rounded by half its shorter side): a WinUI shape drawing
   the fill, else the stroke (strokeLineWidth wide, centered on the outline as SwiftUI's stroke),
   else filled with the foreground (its own or inherited foregroundStyle, else the theme's text
   color), as SwiftUI's shapes default to the foreground style.
 - A continuous cornerStyle or Capsule style is drawn circular, as on Linux.
*/

import CWinUI

extension Color: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let fill = try FillLayout()
        node.state = fill
        return fill.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let paint: Paint?
        if let value = node.model.value as? ColorSpec {
            paint = Paint.paint(value, role: .background)
        } else {
            paint = Paint.parse(Props(node.properties).color, role: .background)
        }
        Paint.apply(paint, ActionUIWinUIBrushBackground, to: view, what: "a Color")
    }
}

/// The shape every shape element draws, kept in the node's state with its fill layout.
@MainActor final class ShapeState {
    let fill: FillLayout
    let shape: WinUIObject

    init(fill: FillLayout, shape: WinUIObject) {
        self.fill = fill
        self.shape = shape
    }
}

@MainActor enum ShapeViews {
    static func make(_ node: RenderNode, _ kind: ActionUIWinUIShapeKind) throws(WinUIError) -> WinUIObject {
        guard let shape = WinUIObject(adopting: actionUIWinUIShapeCreate(kind)) else {
            throw WinUIError.last("creating a shape")
        }
        let fill = try FillLayout(child: shape)
        node.state = ShapeState(fill: fill, shape: shape)
        return fill.panel.object
    }

    /// Draws the fill, else the stroke, else fills with the foreground; a style that does not parse
    /// counts as none, as on Apple and Linux. The stroke is centered on the outline (FillLayout).
    /// `cornerRadius` (a RoundedRectangle's) is clamped by FillLayout at each arrange.
    static func update(_ node: RenderNode, fill: String?, stroke: String?, lineWidth: Double, cornerRadius: Double? = nil) {
        guard let state = node.state as? ShapeState else { return }
        let shape = state.shape
        var strokeWidth = 0.0
        let tint = node.textAppearance.tint
        if let paint = Paint.parse(fill, role: .background, tint: tint) {
            Paint.apply(paint, ActionUIWinUIBrushFill, to: shape, what: "a shape's fill")
            Paint.apply(nil, ActionUIWinUIBrushStroke, to: shape, what: "a shape's stroke")
        } else if let paint = Paint.parse(stroke, role: .foreground, tint: tint) {
            Paint.apply(nil, ActionUIWinUIBrushFill, to: shape, what: "a shape's fill")
            Paint.apply(paint, ActionUIWinUIBrushStroke, to: shape, what: "a shape's stroke")
            // As the shim takes it: a width that is not a positive number draws no stroke.
            strokeWidth = lineWidth.isFinite && lineWidth > 0 ? lineWidth : 0
        } else {
            let foreground = Paint.parse(node.textAppearance.foreground, role: .foreground, tint: tint) ?? .theme("TextFillColorPrimaryBrush")
            Paint.apply(foreground, ActionUIWinUIBrushFill, to: shape, what: "a shape's fill")
            Paint.apply(nil, ActionUIWinUIBrushStroke, to: shape, what: "a shape's stroke")
        }
        if !actionUIWinUIShapeSetStrokeThickness(shape.pointer, strokeWidth) {
            ActionUIModel.shared.logger.log("Shape: \(WinUIError.last("setting a shape's stroke width"))", .error)
        }
        let layout = state.fill
        if let cornerRadius, layout.cornerRadius != cornerRadius {
            layout.cornerRadius = cornerRadius
            layout.panel.invalidateLayout()
        }
        if layout.childOutset != strokeWidth / 2 {
            layout.childOutset = strokeWidth / 2
            layout.panel.invalidateLayout()
        }
    }
}

extension Rectangle: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try ShapeViews.make(node, ActionUIWinUIShapeRectangle)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeViews.update(node, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }
}

extension RoundedRectangle: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try ShapeViews.make(node, ActionUIWinUIShapeRoundedRectangle)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeViews.update(node, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth,
                          cornerRadius: props.cornerRadius)
    }
}

extension Ellipse: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try ShapeViews.make(node, ActionUIWinUIShapeEllipse)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeViews.update(node, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }
}

extension Circle: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let view = try ShapeViews.make(node, ActionUIWinUIShapeCircle)
        (node.state as? ShapeState)?.fill.squareChild = true
        return view
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeViews.update(node, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }
}

extension Capsule: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let view = try ShapeViews.make(node, ActionUIWinUIShapeCapsule)
        // Rounded by half its shorter side, at whatever size it is given.
        (node.state as? ShapeState)?.fill.cornerRadius = .infinity
        return view
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        ShapeViews.update(node, fill: props.fill, stroke: props.stroke, lineWidth: props.strokeLineWidth)
    }
}
