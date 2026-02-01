// ActionUI/Helpers/CanvasRenderer.swift

import SwiftUI

struct CanvasRenderer {
    
    private static func numbers(from elements: ArraySlice<Any>, logger: any ActionUILogger) -> [CGFloat] {
        elements.map { element in
            if let n = element as? NSNumber { return CGFloat(n.doubleValue) }
            if let d = element as? Double   { return CGFloat(d) }
            if let f = element as? Float    { return CGFloat(f) }
            if let i = element as? Int      { return CGFloat(i) }
            logger.log("Invalid number: \(element)", .warning)
            return 0.0
        }
    }
    
    static func draw(
        _ operations: [[String: Any]],
        into context: inout GraphicsContext,
        size: CGSize,
        coordMode: String,
        logger: any ActionUILogger
    ) {
        for op in operations {
            guard let type = op["type"] as? String else { continue }
            
            switch type.lowercased() {
            case "fill":
                guard let path = makePath(op["path"] as? [String: Any], size: size, coordMode: coordMode, logger: logger) else { continue }
                
                if let gradDict = op["gradient"] as? [String: Any],
                   let shading = makeShading(gradDict, size: size, logger: logger) {
                    context.fill(path, with: shading)
                } else if let colorStr = op["color"] as? String,
                          let color = ColorHelper.resolveColor(colorStr) {
                    context.fill(path, with: .color(color))
                } else {
                    logger.log("No valid color or gradient for fill", .warning)
                }
                
            case "stroke":
                guard let path = makePath(op["path"] as? [String: Any], size: size, coordMode: coordMode, logger: logger),
                      let colorStr = op["color"] as? String,
                      let color = ColorHelper.resolveColor(colorStr) else {
                    logger.log("Missing/invalid path or color for stroke", .warning)
                    continue
                }
                
                let style = StrokeStyle(
                    lineWidth: op.cgFloat(forKey: "lineWidth") ?? 1,
                    lineCap: CGLineCap.fromString(op["lineCap"] as? String ?? "butt"),
                    lineJoin: CGLineJoin.fromString(op["lineJoin"] as? String ?? "miter"),
                    miterLimit: op.cgFloat(forKey: "miterLimit") ?? 10,
                    dash: op.cgFloatArray(forKey: "dash") ?? [],
                    dashPhase: op.cgFloat(forKey: "dashPhase") ?? 0
                )
                context.stroke(path, with: .color(color), style: style)
                
            case "text":
                guard let str = op["text"] as? String,
                      let frameArr = op.cgFloatArray(forKey: "frame"), frameArr.count == 4 else { continue }
                
                let frame = scaleRect(frameArr, size: size, coordMode: coordMode)
                var text = SwiftUI.Text(str)
                
                if let sz = op.cgFloat(forKey: "fontSize") {
                    text = text.font(.system(size: sz))
                }
                if let weightStr = op["fontWeight"] as? String,
                   let weight = SwiftUI.Font.Weight.fromString(weightStr) {
                    text = text.fontWeight(weight)
                }
                text = text.foregroundColor(
                    ColorHelper.resolveColor(op["color"] as? String) ?? .black
                )
                
                if op["alignment"] as? String != nil {
                    logger.log("Text alignment currently not supported in Canvas – default alignment used", .info)
                }
                
                context.draw(text, in: frame)
                
            case "image":
                guard let frameArr = op.cgFloatArray(forKey: "frame"), frameArr.count == 4 else { continue }
                let frame = scaleRect(frameArr, size: size, coordMode: coordMode)
                
                if let img = resolveImage(from: op) {
                    let opacity = op.double(forKey: "opacity") ?? 1.0
                    context.opacity = opacity
                    
                    context.draw(img, in: frame)
                    
                    context.opacity = 1.0
                } else {
                    logger.log("Failed to resolve image", .warning)
                }
                
            case "clip":
                if let path = makePath(op["path"] as? [String: Any], size: size, coordMode: coordMode, logger: logger) {
                    context.clip(to: path)
                }
                
            case "translate":
                context.translateBy(
                    x: op.cgFloat(forKey: "x") ?? 0,
                    y: op.cgFloat(forKey: "y") ?? 0
                )
                
            case "scale":
                context.scaleBy(
                    x: op.cgFloat(forKey: "x") ?? 1,
                    y: op.cgFloat(forKey: "y") ?? 1
                )
                
            case "rotate":
                if let deg = op.cgFloat(forKey: "angle") {
                    context.rotate(by: .degrees(deg))
                }
                
            case "shadow":
                let color = ColorHelper.resolveColor(op["color"] as? String) ?? .black
                let radius = op.cgFloat(forKey: "radius") ?? 0.005
                let offsetX = op.cgFloat(forKey: "x") ?? 0.002
                let offsetY = op.cgFloat(forKey: "y") ?? 0.004
                
                let blend = GraphicsContext.BlendMode.fromString(op["blendMode"] as? String ?? "normal")
                
                context.addFilter(.shadow(
                    color: color,
                    radius: radius,
                    x: offsetX,
                    y: offsetY,
                    blendMode: blend
                ))
                
            case "blur":
                if let r = op.cgFloat(forKey: "radius") {
                    context.addFilter(.blur(radius: r))
                } else {
                    logger.log("Blur missing radius", .warning)
                }
                
            case "layer":
                guard let frameArr = op.cgFloatArray(forKey: "frame"), frameArr.count == 4 else { continue }
                let frame = scaleRect(frameArr, size: size, coordMode: coordMode)
                
                let opacity = op.double(forKey: "opacity") ?? 1.0
                
                if let subOps = op["operations"] as? [[String: Any]] {
                    context.drawLayer { subContext in
                        var subCtx = subContext
                        subCtx.translateBy(x: frame.origin.x, y: frame.origin.y)
                        subCtx.opacity = opacity
                        draw(subOps, into: &subCtx, size: frame.size, coordMode: coordMode, logger: logger)
                    }
                }
                
            default:
                logger.log("Unknown operation type: \(type)", .warning)
            }
        }
    }
    
    // ─── Helpers ────────────────────────────────────────────────────────────────
    
    private static func makePath(
        _ dict: [String: Any]?,
        size: CGSize,
        coordMode: String,
        logger: any ActionUILogger
    ) -> SwiftUI.Path? {
        guard let dict, let type = dict["type"] as? String else {
            logger.log("Missing or invalid path type", .warning)
            return nil
        }
        
        var path = SwiftUI.Path()
        
        let scaleX: (CGFloat) -> CGFloat = { coordMode == "points" ? $0 : $0 * size.width }
        let scaleY: (CGFloat) -> CGFloat = { coordMode == "points" ? $0 : $0 * size.height }
        let scaleMin: (CGFloat) -> CGFloat = { coordMode == "points" ? $0 : $0 * min(size.width, size.height) }
        
        switch type.lowercased() {
        case "circle":
            guard let centerArr = dict.cgFloatArray(forKey: "center"), centerArr.count == 2,
                  let radius = dict.cgFloat(forKey: "radius") else {
                logger.log("Invalid circle: missing center or radius", .warning)
                return nil
            }
            let cx = scaleX(centerArr[0])
            let cy = scaleY(centerArr[1])
            let r = scaleMin(radius)
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            
        case "ellipse":
            guard let frameArr = dict.cgFloatArray(forKey: "frame"), frameArr.count == 4 else {
                logger.log("Invalid ellipse: frame must be [x,y,w,h]", .warning)
                return nil
            }
            let rect = CGRect(
                x: scaleX(frameArr[0]),
                y: scaleY(frameArr[1]),
                width: scaleX(frameArr[2]),
                height: scaleY(frameArr[3])
            )
            path.addEllipse(in: rect)
            
        case "rect":
            guard let x = dict.cgFloat(forKey: "x"),
                  let y = dict.cgFloat(forKey: "y"),
                  let w = dict.cgFloat(forKey: "width"),
                  let h = dict.cgFloat(forKey: "height") else {
                logger.log("Invalid rect: missing x/y/width/height", .warning)
                return nil
            }
            path.addRect(CGRect(
                x: scaleX(x),
                y: scaleY(y),
                width: scaleX(w),
                height: scaleY(h)
            ))
            
        case "roundedrect":
            guard let x = dict.cgFloat(forKey: "x"),
                  let y = dict.cgFloat(forKey: "y"),
                  let w = dict.cgFloat(forKey: "width"),
                  let h = dict.cgFloat(forKey: "height") else {
                logger.log("Invalid roundedRect: missing x/y/width/height", .warning)
                return nil
            }
            
            let corner: CGFloat
            if let cr = dict.cgFloat(forKey: "cornerRadius") {
                corner = scaleMin(cr)
            } else if let corners = dict.cgFloatArray(forKey: "cornerRadii"), corners.count == 4 {
                corner = scaleMin(corners[0])
            } else {
                corner = 0
            }
            
            let rect = CGRect(
                x: scaleX(x),
                y: scaleY(y),
                width: scaleX(w),
                height: scaleY(h)
            )
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
            
        case "path":
            guard let commands = dict["commands"] as? [[Any]] else {
                logger.log("Custom path missing 'commands' array", .warning)
                return nil
            }
            
            for cmd in commands {
                guard let name = cmd.first as? String else { continue }
                let args = numbers(from: cmd.dropFirst(), logger: logger)
                
                switch name.lowercased() {
                case "moveto":
                    if args.count >= 2 {
                        path.move(to: CGPoint(x: scaleX(args[0]), y: scaleY(args[1])))
                    }
                    
                case "lineto":
                    if args.count >= 2 {
                        path.addLine(to: CGPoint(x: scaleX(args[0]), y: scaleY(args[1])))
                    }
                    
                case "quadraticcurveto", "quadcurveto":
                    if args.count >= 4 {
                        let control = CGPoint(x: scaleX(args[0]), y: scaleY(args[1]))
                        let end = CGPoint(x: scaleX(args[2]), y: scaleY(args[3]))
                        path.addQuadCurve(to: end, control: control)
                    }
                    
                case "curveto", "cubiccurveto":
                    if args.count >= 6 {
                        let c1 = CGPoint(x: scaleX(args[0]), y: scaleY(args[1]))
                        let c2 = CGPoint(x: scaleX(args[2]), y: scaleY(args[3]))
                        let end = CGPoint(x: scaleX(args[4]), y: scaleY(args[5]))
                        path.addCurve(to: end, control1: c1, control2: c2)
                    }
                    
                case "arc":
                    if args.count >= 6 {
                        let center = CGPoint(x: scaleX(args[0]), y: scaleY(args[1]))
                        let radius = scaleMin(args[2])
                        let start = Angle.degrees(args[3])
                        let end = Angle.degrees(args[4])
                         let clock  = args[5] != 0  // 1 = clockwise, 0 = counterclockwise
                        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: clock)
                    }
                    
                case "closepath", "close":
                    path.closeSubpath()
                    
                default:
                    logger.log("Unknown path command: \(name)", .warning)
                }
            }
            
        default:
            logger.log("Unsupported path type: \(type)", .warning)
            return nil
        }
        
        return path.isEmpty ? nil : path
    }
    
    private static func makeShading(
        _ dict: [String: Any],
        size: CGSize,
        logger: any ActionUILogger
    ) -> GraphicsContext.Shading? {
        guard let type = dict["type"] as? String,
              let colorsArr = dict["colors"] as? [String],
              colorsArr.count >= 2 else {
            logger.log("Invalid gradient: missing type or colors", .warning)
            return nil
        }
        
        let colors = colorsArr.compactMap { ColorHelper.resolveColor($0) }
        guard !colors.isEmpty else { return nil }
        
        let gradient = Gradient(colors: colors)
        
        switch type.lowercased() {
        case "linear":
            guard let startArr = dict.cgFloatArray(forKey: "start"), startArr.count == 2,
                  let endArr = dict.cgFloatArray(forKey: "end"), endArr.count == 2 else {
                return nil
            }
            let start = CGPoint(x: startArr[0] * size.width, y: startArr[1] * size.height)
            let end = CGPoint(x: endArr[0] * size.width, y: endArr[1] * size.height)
            return .linearGradient(gradient, startPoint: start, endPoint: end)
            
        case "radial":
            guard let centerArr = dict.cgFloatArray(forKey: "center"), centerArr.count == 2,
                  let endR = dict.cgFloat(forKey: "endRadius") else { return nil }
            let center = CGPoint(x: centerArr[0] * size.width, y: centerArr[1] * size.height)
            let startR = dict.cgFloat(forKey: "startRadius") ?? 0
            return .radialGradient(
                gradient,
                center: center,
                startRadius: startR * min(size.width, size.height),
                endRadius: endR * min(size.width, size.height)
            )
            
        default:
            logger.log("Unsupported gradient type: \(type)", .warning)
            return nil
        }
    }
    
    private static func resolveImage(from op: [String: Any]) -> SwiftUI.Image? {
        if let systemName = op["systemName"] as? String {
            return SwiftUI.Image(from: systemName, interpretation: "systemName")
        }
        
        if let assetName = op["assetName"] as? String {
            return SwiftUI.Image(from: assetName, interpretation: "assetName")
        }
        
        if let resourceName = op["resourceName"] as? String {
            return SwiftUI.Image(from: resourceName, interpretation: "resourceName")
        }
        
        if let filePath = op["filePath"] as? String {
            return SwiftUI.Image(from: filePath, interpretation: "path")
        }
        
        // logger.log("No valid image source (systemName, assetName, or filePath) provided", .warning)
        return nil
    }
    
    private static func scale(_ value: CGFloat, size: CGSize, coordMode: String) -> CGFloat {
        return coordMode == "points" ? value : value * min(size.width, size.height)
    }
    
    private static func scaleRect(_ arr: [CGFloat], size: CGSize, coordMode: String) -> CGRect {
        guard arr.count == 4 else { return .zero }
        if coordMode == "points" {
            return CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
        }
        return CGRect(
            x: arr[0] * size.width,
            y: arr[1] * size.height,
            width: arr[2] * size.width,
            height: arr[3] * size.height
        )
    }
}

extension CGLineCap {
    static func fromString(_ str: String) -> CGLineCap {
        switch str.lowercased() {
        case "round": return .round
        case "square": return .square
        default: return .butt
        }
    }
}

extension CGLineJoin {
    static func fromString(_ str: String) -> CGLineJoin {
        switch str.lowercased() {
        case "round": return .round
        case "bevel": return .bevel
        default: return .miter
        }
    }
}

extension SwiftUI.Font.Weight {
    static func fromString(_ str: String) -> SwiftUI.Font.Weight? {
        switch str.lowercased() {
        case "ultralight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return nil
        }
    }
}

extension TextAlignment {
    static func fromString(_ str: String) -> TextAlignment {
        switch str.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        default: return .center
        }
    }
}

extension GraphicsContext.BlendMode {
    static func fromString(_ str: String) -> GraphicsContext.BlendMode {
        switch str.lowercased() {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        default: return .normal
        }
    }
}
