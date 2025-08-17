/*
 Sample JSON for PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Animating" } },
     "values": [0.0, 1.0, 2.0],
     "trigger": "onAppear" | "onTap" | "onTimer" | "onStateChange",
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
        
        if validatedProperties["content"] == nil {
            print("Warning: PhaseAnimator requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["values"] as? [Double] == nil {
            print("Warning: PhaseAnimator requires 'values'; defaulting to [0.0, 1.0]")
            validatedProperties["values"] = [0.0, 1.0]
        }
        if validatedProperties["trigger"] == nil {
            print("Warning: PhaseAnimator requires 'trigger'; defaulting to 'onAppear'")
            validatedProperties["trigger"] = "onAppear"
        }
        if validatedProperties["trigger"] as? String == "onTimer" {
            if validatedProperties["timerInterval"] == nil {
                print("Warning: onTimer requires 'timerInterval'; defaulting to 1.0")
                validatedProperties["timerInterval"] = 1.0
            }
        }
        if validatedProperties["trigger"] as? String == "onStateChange" {
            if validatedProperties["stateKey"] == nil {
                print("Warning: onStateChange requires 'stateKey'; defaulting to 'default'")
                validatedProperties["stateKey"] = "default"
            }
        }
        if let animation = validatedProperties["animation"] as? [String: Any] {
            var validatedAnimation = animation
            if validatedAnimation["type"] == nil {
                print("Warning: animation requires 'type'; defaulting to 'linear'")
                validatedAnimation["type"] = "linear"
            }
            let animationType = validatedAnimation["type"] as? String ?? "linear"
            if animationType != "spring" && animationType != "interactiveSpring" {
                if validatedAnimation["duration"] == nil {
                    print("Warning: \(animationType) requires 'duration'; defaulting to 1.0")
                    validatedAnimation["duration"] = 1.0
                }
            }
            if animationType == "spring" || animationType == "interactiveSpring" {
                if validatedAnimation["response"] == nil {
                    print("Warning: \(animationType) requires 'response'; defaulting to 0.5")
                    validatedAnimation["response"] = 0.5
                }
                if validatedAnimation["dampingFraction"] == nil {
                    print("Warning: \(animationType) 'dampingFraction' missing; defaulting to 1.0")
                    validatedAnimation["dampingFraction"] = 1.0
                }
                if validatedAnimation["blendDuration"] == nil {
                    validatedAnimation["blendDuration"] = 0.0
                }
            }
            if animationType == "smooth" || animationType == "bouncy" {
                if validatedAnimation["extraBounce"] == nil {
                    validatedAnimation["extraBounce"] = 0.0
                }
            }
            if animationType == "timingCurve" {
                if validatedAnimation["controlPoints"] as? [Double] == nil {
                    print("Warning: timingCurve requires 'controlPoints'; defaulting to [0.0, 0.0, 1.0, 1.0]")
                    validatedAnimation["controlPoints"] = [0.0, 0.0, 1.0, 1.0]
                }
            }
            validatedProperties["animation"] = validatedAnimation
        } else {
            validatedProperties["animation"] = ["type": "linear", "duration": 1.0]
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        if #available(iOS 17.0, macOS 14.0, *) {
            let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let values = properties["values"] as? [Double] ?? [0.0, 1.0]
            let trigger = properties["trigger"] as? String ?? "onAppear"
            let timerInterval = properties["timerInterval"] as? Double ?? 1.0
            let stateKey = properties["stateKey"] as? String ?? "default"
            let animation = properties["animation"] as? [String: Any] ?? ["type": "linear", "duration": 1.0]
            
            // Parse animation parameters
            let animationType = animation["type"] as? String ?? "linear"
            let duration = animation["duration"] as? Double ?? 1.0
            let response = animation["response"] as? Double ?? 0.5
            let dampingFraction = animation["dampingFraction"] as? Double ?? 1.0
            let blendDuration = animation["blendDuration"] as? Double ?? 0.0
            let extraBounce = animation["extraBounce"] as? Double ?? 0.0
            let controlPoints = animation["controlPoints"] as? [Double] ?? [0.0, 0.0, 1.0, 1.0]
            
            // Use a state to manage the trigger
            @State var animationTrigger: Int = 0 // Use Int for multiple phase cycles
            
            var view: any SwiftUI.View = SwiftUI.PhaseAnimator(values, trigger: animationTrigger) { value in
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
                    .opacity(value) // Example: Apply value as opacity
            } animation: { _ in
                switch animationType {
                case "linear":
                    return .linear(duration: duration)
                case "easeIn":
                    return .easeIn(duration: duration)
                case "easeOut":
                    return .easeOut(duration: duration)
                case "easeInOut":
                    return .easeInOut(duration: duration)
                case "spring":
                    return .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
                case "interactiveSpring":
                    return .interactiveSpring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
                case "smooth":
                    return .smooth(duration: duration, extraBounce: extraBounce)
                case "bouncy":
                    return .bouncy(duration: duration, extraBounce: extraBounce)
                case "timingCurve":
                    return .timingCurve(controlPoints[0], controlPoints[1], controlPoints[2], controlPoints[3], duration: duration)
                default:
                    return .linear(duration: 1.0)
                }
            }
            
            // Conditionally apply modifiers based on trigger
            if trigger == "onAppear" {
                view = view.onAppear {
                    animationTrigger += 1 // Start animation
                }
            } else if trigger == "onTap" {
                view = view.onTapGesture {
                    animationTrigger += 1 // Advance on tap
                }
            } else if trigger == "onTimer" {
                view = view.onReceive(Timer.publish(every: timerInterval, on: .main, in: .common).autoconnect()) { _ in
                    animationTrigger += 1 // Advance on timer
                }
            } else if trigger == "onStateChange" {
                view = view.onChange(of: (state.wrappedValue[0] as? [String: Any])?[stateKey] as? Int, initial: false) { oldValue, newValue in
                    if let newValue = newValue {
                        animationTrigger = newValue // Sync with state
                    }
                }
            }
            
            return view
        } else {
            print("Warning: PhaseAnimator requires iOS 17.0 or macOS 14.0")
            return SwiftUI.EmptyView()
        }
    }
}
