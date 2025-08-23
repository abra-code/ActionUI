// Sources/Views/PhaseAnimator.swift
/*
 Sample JSON for PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in properties["content"] by StaticElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "values": [0.0, 1.0, 2.0],
     "trigger": "onAppear", // "onAppear", "onTap", "onTimer", "onStateChange"
     "timerInterval": 2.0, // Optional, for onTimer
     "stateKey": "counter", // Optional, for onStateChange
     "animation": {
       "type": "spring", // linear, easeIn, easeOut, easeInOut, spring, interactiveSpring, smooth, bouncy, timingCurve
       "duration": 0.5, // For linear, easeIn, easeOut, easeInOut, smooth, bouncy, timingCurve
       "response": 0.5, // For spring, interactiveSpring
       "dampingFraction": 0.7, // Optional for spring, interactiveSpring
       "blendDuration": 0.0, // Optional for spring, interactiveSpring
       "extraBounce": 0.1, // Optional for smooth, bouncy
       "controlPoints": [0.2, 0.8, 0.4, 1.0] // For timingCurve (c0x, c0y, c1x, c1y)
     }
   }
 }
*/

import SwiftUI
internal import Combine // Explicitly set access level to internal

struct PhaseAnimator: ActionUIViewConstruction {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate content
        // Note: Expects content in properties["content"] as any ActionUIElement, set by StaticElement.init(from:).
        if let content = validatedProperties["content"] as? any ActionUIElement {
            logger.log("Validated content: \((content as? StaticElement)?.type ?? "nil")", .debug)
        } else {
            logger.log("PhaseAnimator requires 'content'; defaulting to EmptyView", .warning)
            validatedProperties["content"] = StaticElement(id: StaticElement.generateNegativeID(), type: "EmptyView", properties: [:], children: nil)
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        if #available(iOS 17.0, macOS 14.0, *) {
            let content = properties["content"] as? any ActionUIElement ?? StaticElement(id: StaticElement.generateNegativeID(), type: "EmptyView", properties: [:], children: nil)
            let values = (properties["values"] as? [Double]) ?? [0.0, 1.0]
            let trigger = (properties["trigger"] as? String) ?? "onAppear"
            let timerInterval = (properties.double(forKey: "timerInterval")) ?? 1.0
            let stateKey = (properties["stateKey"] as? String) ?? "counter"
            let animationDict = (properties["animation"] as? [String: Any]) ?? ["type": "linear", "duration": 1.0]
            
            @State var animationTrigger: Int = 0
            
            // Define animation
            let animation: Animation
            let type = animationDict["type"] as? String ?? "linear"
            let duration = animationDict.double(forKey: "duration") ?? 1.0
            let response = animationDict.double(forKey: "response") ?? 0.5
            let dampingFraction = animationDict.double(forKey: "dampingFraction") ?? 0.7
            let blendDuration = animationDict.double(forKey: "blendDuration") ?? 0.0
            let extraBounce = animationDict.double(forKey: "extraBounce") ?? 0.0
            let controlPoints = animationDict["controlPoints"] as? [Double] ?? [0.0, 0.0, 1.0, 1.0] // TODO: array of doubles
            
            switch type {
            case "linear":
                animation = .linear(duration: duration)
            case "easeIn":
                animation = .easeIn(duration: duration)
            case "easeOut":
                animation = .easeOut(duration: duration)
            case "easeInOut":
                animation = .easeInOut(duration: duration)
            case "spring":
                animation = .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
            case "interactiveSpring":
                animation = .interactiveSpring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
            case "smooth":
                animation = .smooth(duration: duration, extraBounce: extraBounce)
            case "bouncy":
                animation = .bouncy(duration: duration, extraBounce: extraBounce)
            case "timingCurve":
                animation = .timingCurve(controlPoints[0], controlPoints[1], controlPoints[2], controlPoints[3], duration: duration)
            default:
                animation = .linear(duration: 1.0)
            }
            
            return SwiftUI.PhaseAnimator(
                values,
                trigger: animationTrigger,
                content: { value in
                    ActionUIView(element: content, state: state, windowUUID: windowUUID)
                        .opacity(value)
                },
                animation: { _ in animation }
            )
            .onAppear {
                if trigger == "onAppear" {
                    animationTrigger += 1
                }
            }
            .onTapGesture {
                if trigger == "onTap" {
                    animationTrigger += 1
                }
            }
            .onReceive(Timer.publish(every: timerInterval, on: .main, in: .common).autoconnect()) { _ in
                if trigger == "onTimer" {
                    animationTrigger += 1
                }
            }
            .onChange(of: (state.wrappedValue[0] as? [String: Any])?[stateKey] as? Int, initial: false) { _, newValue in
                if trigger == "onStateChange", let newValue = newValue {
                    animationTrigger = newValue
                }
            }
        } else {
            logger.log("PhaseAnimator requires iOS 17.0 or macOS 14.0; returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        return view
    }
}
