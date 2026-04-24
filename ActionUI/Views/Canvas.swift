// Sources/Views/Canvas.swift
/*
 Sample JSON for Canvas:
 {
   "type": "Canvas",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction, default none
   "properties": {
     "operations": [     // Optional: Array of drawing operations, default []
       // Fill with solid color
       {
         "type": "fill",
         "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.4 }, // Required
         "color": "#FF0000"  // Optional, default "black". Mutually exclusive with "gradient"
         // or "gradient": { "type": "linear", "start": [0,0], "end": [1,1], "colors": ["#FF0000","#0000FF"], "locations": [0.0,1.0] }
       },
       // Stroke
       {
         "type": "stroke",
         "path": { ... },    // Required
         "color": "#0000FF", // Required
         "lineWidth": 0.02,  // Optional, default 1
         "lineCap": "round", // Optional ("butt","round","square"), default "butt"
         "dash": [0.05,0.02] // Optional, default []
       },
       // Text
       {
         "type": "text",
         "text": "Hello",    // Required
         "frame": [0.2,0.4,0.6,0.1], // Required [x,y,w,h] normalized
         "fontSize": 0.05,   // Optional, default ~0.05 (relative to height)
         "fontWeight": "bold", // Optional, default "regular"
         "color": "#333",    // Optional, default "black"
         "alignment": "center" // Optional ("left","center","right"), default "left"
       },
       // Image
       {
         "type": "image",
         "frame": [0.3,0.3,0.4,0.4], // Required
         "systemName": "star.fill",   // Optional – one of these three required
         // "assetName": "myImage",
         // "resourceName": "yourImage.jpg"
         // "filePath": "images/logo.png",
         "opacity": 0.8,     // Optional, default 1.0
         "resizingMode": "tile" // Optional ("stretch","tile","original"), default "stretch"
       },
       // Clip (affects subsequent ops)
       {
         "type": "clip",
         "path": { ... }     // Required
       },
       // Transforms (cumulative)
       { "type": "translate", "x": 0.1, "y": 0.05 }, // x/y optional, default 0
       { "type": "scale", "x": 1.2, "y": 1.2 },      // x/y optional, default 1
       { "type": "rotate", "angle": 45 },            // angle required (degrees)

       // Shadow (drop shadow filter – affects subsequent ops)
       {
         "type": "shadow",
         "color": "#000000",     // Optional, default black
         "radius": 0.012,        // Optional (normalized), default 0.005
         "x": 0.004,             // Optional (normalized offset), default 0.002
         "y": 0.006,             // Optional (normalized offset), default 0.004
         "blendMode": "normal",  // Optional, default "normal"
         "drawAbove": false      // Optional bool, default false (shadow below content)
       },

       // Blur (affects subsequent ops)
       {
         "type": "blur",
         "radius": 0.015         // Required (normalized to min dimension)
       },

       // Layer (isolates state – opacity, blend, filters, transforms, clips)
       {
         "type": "layer",
         "frame": [0.1,0.1,0.8,0.8], // Required
         "opacity": 0.75,            // Optional, default 1.0
         "blendMode": "screen",      // Optional, default "normal"
         "operations": [ ... ]       // Optional, default [], same format as Canvas operations
       }
     ],
     "backgroundColor": "#F5F5F5", // Optional, default clear
     "coordinateMode": "normalized", // Optional ("normalized"|"points"), default "normalized"
     "actionID": "canvasTap"       // Optional
   }
 }

 // Colors: #RRGGBB[AA], named, systemRed, etc.
 // Gradients: linear / radial (see earlier examples)
 
 // Paths/Shapes in "path" key:
 // All coordinates, sizes, radii, etc. are numbers (integers or decimals).
 // When "coordinateMode": "normalized" (default), most values are in the 0.0 to 1.0 range
 // (0 = left/top, 1 = right/bottom of the canvas).
 // When "coordinateMode": "points", values are absolute pixels/points.

 // Supported shape types:

 // circle
 // {
 //   "type": "circle",
 //   "center": [0.5, 0.5],     // [x, y] center position
 //   "radius": 0.4             // radius (0.0–0.5 is common)
 // }

 // ellipse
 // {
 //   "type": "ellipse",
 //   "frame": [0.1, 0.1, 0.8, 0.8]   // [x, y, width, height]
 // }

 // rect
 // {
 //   "type": "rect",
 //   "x": 0.1,
 //   "y": 0.1,
 //   "width": 0.8,
 //   "height": 0.8
 // }

 // roundedRect
 // {
 //   "type": "roundedRect",
 //   "x": 0.1,
 //   "y": 0.1,
 //   "width": 0.8,
 //   "height": 0.8,
 //   "cornerRadius": 0.05             // single radius for all corners (optional, default 0)
 //   // or
 //   "cornerRadii": [0.05, 0.1, 0.05, 0.1]   // [top-left, top-right, bottom-right, bottom-left] (optional)
 // }

 // path (custom Bézier path)
 // {
 //   "type": "path",
 //   "commands": [
 //     // Array of commands. Each command is an array: [name, arg1, arg2, ...]
 //     // Start with "moveTo" in most cases
 //     ["moveTo", 0.5, 0.1],                    // move pen without drawing
 //     ["lineTo", 0.6, 0.4],                    // straight line to point
 //     ["quadraticCurveTo", 0.7, 0.3, 0.8, 0.5], // [controlX, controlY, endX, endY]
 //     ["curveTo", 0.9, 0.2, 1.0, 0.6, 0.8, 0.8], // cubic [c1x, c1y, c2x, c2y, endX, endY]
 //     ["arc", 0.5, 0.5, 0.3, 0, 180, 0],       // [centerX, centerY, radius, startAngleDegrees, endAngleDegrees, clockwise (0 or 1)]
 //     ["closePath"]                            // close the current subpath (optional)
 //   ]
 // }

 // Practical example – simple star-like shape
 // {
 //   "type": "path",
 //   "commands": [
 //     ["moveTo", 0.5, 0.1],
 //     ["lineTo", 0.6, 0.4],
 //     ["lineTo", 0.9, 0.4],
 //     ["lineTo", 0.65, 0.6],
 //     ["lineTo", 0.75, 0.9],
 //     ["lineTo", 0.5, 0.7],
 //     ["lineTo", 0.25, 0.9],
 //     ["lineTo", 0.35, 0.6],
 //     ["lineTo", 0.1, 0.4],
 //     ["lineTo", 0.4, 0.4],
 //     ["closePath"]
 //   ]
 // }

 // Tips for custom paths:
 // - Always start with "moveTo" unless continuing a previous subpath
 // - Angles in "arc" are in degrees (0–360), not radians
 // - Clockwise: 1 = clockwise, 0 = counter-clockwise
 // - Invalid commands or wrong number of arguments are ignored (logged in debug)
 // - You can have multiple subpaths (multiple moveTo + closePath sequences)
 // - All numbers can be integers or decimals — both work fine
 
 */

import SwiftUI

struct Canvas: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var valueType: Any.Type = Void.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties
        
        if let ops = validated["operations"] as? [[String: Any]] {
            validated["operations"] = validateOperations(ops, logger: logger)
        } else if validated["operations"] != nil {
            logger.log("Invalid operations type", .warning)
            validated["operations"] = nil
        }
        
        if let bg = validated["backgroundColor"], !(bg is String) {
            validated["backgroundColor"] = nil
        }
        
        // Validate coordinateMode (optional String: "normalized" or "points")
        if let modeAny = validated["coordinateMode"] {
            if let mode = modeAny as? String, (mode == "normalized" || mode == "points") {
                // valid
            } else {
                logger.log("Invalid coordinateMode value: \(modeAny), defaulting to normalized", .warning)
                validated["coordinateMode"] = nil  // or set "normalized" if preferred
            }
        }
        
        return validated
    }
    
    private static func validateOperations(_ ops: [[String: Any]], logger: any ActionUILogger) -> [[String: Any]] {
        ops.compactMap { op -> [String: Any]? in
            guard let type = op["type"] as? String else { return nil }
            
            var v = op
            
            switch type.lowercased() {
            case "fill", "stroke", "clip":
                if op["path"] as? [String: Any] == nil { return nil }
                
            case "text":
                if op["text"] as? String == nil || (op["frame"] as? [Any])?.count != 4 { return nil }
                
            case "image":
                let sources = ["systemName", "assetName", "resourceName", "filePath"].filter { op[$0] != nil }
                if sources.count != 1 || (op["frame"] as? [Any])?.count != 4 { return nil }
                
            case "shadow":
                // all optional except type
                break
                
            case "blur":
                if let radius = op.cgFloat(forKey: "radius") {
                    if radius <= 0 {
                        logger.log("Blur radius should be > 0, got \(radius)", .warning)
                    }
                } else {
                    logger.log("Blur missing valid 'radius' (expected number)", .warning)
                    return nil
                }
            
            case "layer":
                if (op["frame"] as? [Any])?.count != 4 { return nil }
                if let sub = op["operations"] as? [[String: Any]] {
                    v["operations"] = validateOperations(sub, logger: logger)
                }
                
            default:
                if !["translate", "scale", "rotate", "stroke", "fill"].contains(type.lowercased()) {
                    logger.log("Unknown op type: \(type)", .warning)
                    return nil
                }
            }
            return v
        }
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let ops = properties["operations"] as? [[String: Any]] ?? []
        let bg = ColorHelper.resolveColor(properties["backgroundColor"] as? String) ?? .clear
        let coord = properties["coordinateMode"] as? String ?? "normalized"
        let actionID = properties["actionID"] as? String
        
        return SwiftUI.Canvas { context, size in
            if bg != .clear {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            }
            
            var mutableContext = context
            CanvasRenderer.draw(ops, into: &mutableContext, size: size, coordMode: coord, logger: logger)
        }
        .onTapGesture {
            if let id = actionID {
                ActionUIModel.shared.actionHandler(id, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }
    }
}
