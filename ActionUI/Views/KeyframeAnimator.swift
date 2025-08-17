/*
 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Animating" } },
     "initialValue": { "opacity": 0.0, "scale": 1.0, "rotation": 0.0 },
     "trigger": "onAppear" | "onTap" | "onTimer" | "onStateChange",
     "timerInterval": 2.0, // Optional, for onTimer
     "stateKey": "counter", // Optional, for onStateChange
     "repeat": { "count": 3, "autoreverses": true }, // Optional
     "delay": 1.0, // Optional
     "keyframes": {
       "0%": { "type": "linear", "value": { "opacity": 0.0, "scale": 0.5 }, "duration": 0.8 },
       "50%": { "type": "spring", "value": { "opacity": 1.0, "scale": 1.5 }, "duration": 0.5, "response": 0.4, "dampingRatio": 0.6 },
       "100%": { "type": "cubic", "value": { "opacity": 0.5, "scale": 1.0 }, "duration": 0.6, "startVelocity": 0.2, "endVelocity": 0.4 },
       // For ease-in-out effect, use "spring" with response: 0.5, dampingRatio: 1.0
       "25%": { "type": "spring", "value": { "opacity": 0.5 }, "duration": 0.4, "response": 0.5, "dampingRatio": 1.0 }
     },
     // Inherited: padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, disabled, actionID
   }
 }
*/

import SwiftUI
internal import Combine // Required for Timer.publish in onTimer trigger

// Define a value type for animatable properties
struct AnimationValues: Equatable {
    var opacity: Double = 1.0
    var scale: Double = 1.0
    var rotation: Double = 0.0
}

struct KeyframeAnimator: ActionUIViewConstruction {
    static var valueType: Any.Type { AnimationValues.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate content
        if validatedProperties["content"] == nil {
            print("Warning: KeyframeAnimator requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        
        // Validate initialValue
        if validatedProperties["initialValue"] == nil {
            print("Warning: KeyframeAnimator requires 'initialValue'; defaulting to opacity: 0.0, scale: 1.0, rotation: 0.0")
            validatedProperties["initialValue"] = ["opacity": 0.0, "scale": 1.0, "rotation": 0.0]
        }
        
        // Validate trigger
        if validatedProperties["trigger"] == nil {
            print("Warning: KeyframeAnimator requires 'trigger'; defaulting to 'onAppear'")
            validatedProperties["trigger"] = "onAppear"
        }
        
        // Validate timerInterval for onTimer
        if validatedProperties["trigger"] as? String == "onTimer" {
            if validatedProperties["timerInterval"] == nil {
                print("Warning: onTimer requires 'timerInterval'; defaulting to 1.0")
                validatedProperties["timerInterval"] = 1.0
            }
        }
        
        // Validate stateKey for onStateChange
        if validatedProperties["trigger"] as? String == "onStateChange" {
            if validatedProperties["stateKey"] == nil {
                print("Warning: onStateChange requires 'stateKey'; defaulting to 'default'")
                validatedProperties["stateKey"] = "default"
            }
        }
        
        // Validate keyframes
        if let keyframes = validatedProperties["keyframes"] as? [String: [String: Any]] {
            var validatedKeyframes = keyframes
            for (percent, keyframe) in keyframes {
                var validatedKeyframe = keyframe
                if validatedKeyframe["type"] == nil {
                    print("Warning: keyframe at \(percent) requires 'type'; defaulting to 'linear'")
                    validatedKeyframe["type"] = "linear"
                }
                if validatedKeyframe["value"] == nil {
                    print("Warning: keyframe at \(percent) requires 'value'; defaulting to initialValue")
                    validatedKeyframe["value"] = validatedProperties["initialValue"] as? [String: Any] ?? ["opacity": 0.0, "scale": 1.0, "rotation": 0.0]
                }
                if validatedKeyframe["duration"] == nil {
                    print("Warning: keyframe at \(percent) requires 'duration'; defaulting to 1.0")
                    validatedKeyframe["duration"] = 1.0
                }
                let keyframeType = validatedKeyframe["type"] as? String ?? "linear"
                if keyframeType == "spring" {
                    if validatedKeyframe["response"] == nil {
                        print("Warning: spring keyframe at \(percent) requires 'response'; defaulting to 0.5")
                        validatedKeyframe["response"] = 0.5
                    }
                    if validatedKeyframe["dampingRatio"] == nil {
                        print("Warning: spring keyframe at \(percent) 'dampingRatio' missing; defaulting to 1.0")
                        validatedKeyframe["dampingRatio"] = 1.0
                    }
                }
                if keyframeType == "cubic" {
                    if validatedKeyframe["startVelocity"] == nil {
                        print("Warning: cubic keyframe at \(percent) 'startVelocity' missing; defaulting to nil")
                        validatedKeyframe["startVelocity"] = nil
                    }
                    if validatedKeyframe["endVelocity"] == nil {
                        print("Warning: cubic keyframe at \(percent) 'endVelocity' missing; defaulting to nil")
                        validatedKeyframe["endVelocity"] = nil
                    }
                }
                if !["linear", "spring", "cubic"].contains(keyframeType) {
                    print("Warning: keyframe at \(percent) has invalid type '\(keyframeType)'; defaulting to 'linear'")
                    validatedKeyframe["type"] = "linear"
                }
                validatedKeyframes[percent] = validatedKeyframe
            }
            validatedProperties["keyframes"] = validatedKeyframes
        } else {
            print("Warning: KeyframeAnimator requires 'keyframes'; defaulting to linear opacity animation")
            validatedProperties["keyframes"] = [
                "0%": ["type": "linear", "value": ["opacity": 0.0], "duration": 1.0],
                "100%": ["type": "linear", "value": ["opacity": 1.0], "duration": 1.0]
            ]
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        if #available(iOS 17.0, macOS 14.0, *) {
            let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let initialValueDict = properties["initialValue"] as? [String: Any] ?? ["opacity": 0.0, "scale": 1.0, "rotation": 0.0]
            let trigger = properties["trigger"] as? String ?? "onAppear"
            let timerInterval = properties["timerInterval"] as? Double ?? 1.0
            let stateKey = properties["stateKey"] as? String ?? "default"
            let repeatDict = properties["repeat"] as? [String: Any]
            let delay = properties["delay"] as? Double ?? 0.0
            
            // Calculate total animation duration for repeat timing
            let keyframes = properties["keyframes"] as? [String: [String: Any]] ?? [
                "0%": ["type": "linear", "value": ["opacity": 0.0], "duration": 1.0],
                "100%": ["type": "linear", "value": ["opacity": 1.0], "duration": 1.0]
            ]
            let totalDuration = keyframes.reduce(0.0) { sum, keyframe in
                sum + (keyframe.value["duration"] as? Double ?? 1.0)
            }
            
            // Extract repeat parameters
            let repeatCount = repeatDict?["count"] as? Int
            let autoreverses = repeatDict?["autoreverses"] as? Bool ?? false
            
            // Convert initialValue dictionary to AnimationValues
            let initialValue = AnimationValues(
                opacity: initialValueDict["opacity"] as? Double ?? 0.0,
                scale: initialValueDict["scale"] as? Double ?? 1.0,
                rotation: initialValueDict["rotation"] as? Double ?? 0.0
            )
            
            // Pre-process keyframes into sorted (time, keyframe) pairs
            let keyframeValues = keyframes
                .map { (key: $0.key, value: $0.value) }
                .compactMap { (key, keyframe) -> (Double, [String: Any])? in
                    guard let _ = keyframe["type"], let _ = keyframe["value"], let _ = keyframe["duration"] else { return nil }
                    return (parsePercent(key), keyframe)
                }
                .sorted { $0.0 < $1.0 }
            
            // State for managing animation trigger and repeat logic
            @State var animationTrigger: Int = 0
            @State var currentRepeatCount: Int = 0
            
            // Helper to handle repeat and delay logic
            func startAnimation() {
                currentRepeatCount = 0
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        animationTrigger += 1
                    }
                } else {
                    animationTrigger += 1
                }
            }
            
            // Helper to update state for actionID
            func handleAction() {
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
            
            var view: any SwiftUI.View = SwiftUI.KeyframeAnimator(
                initialValue: initialValue,
                trigger: animationTrigger
            ) { value in
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
                    .opacity(value.opacity)
                    .scaleEffect(value.scale)
                    .rotationEffect(.degrees(value.rotation))
            } keyframes: { _ in
                KeyframeTrack(\AnimationValues.opacity) {
                    for (time, keyframe) in keyframeValues {
                        let type = keyframe["type"] as? String ?? "linear"
                        let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                        let opacity = valueDict["opacity"] as? Double ?? 0.0
                        let duration = keyframe["duration"] as? Double ?? 1.0
                        switch type {
                        case "linear":
                            LinearKeyframe(opacity, duration: duration)
                        case "spring":
                            let response = keyframe["response"] as? Double ?? 0.5
                            let dampingRatio = keyframe["dampingRatio"] as? Double ?? 1.0
                            SpringKeyframe(opacity, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                        case "cubic":
                            let startVelocity = keyframe["startVelocity"] as? Double
                            let endVelocity = keyframe["endVelocity"] as? Double
                            CubicKeyframe(opacity, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                        default:
                            LinearKeyframe(opacity, duration: 1.0)
                        }
                    }
                }
                KeyframeTrack(\AnimationValues.scale) {
                    for (time, keyframe) in keyframeValues {
                        let type = keyframe["type"] as? String ?? "linear"
                        let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                        let scale = valueDict["scale"] as? Double ?? 1.0
                        let duration = keyframe["duration"] as? Double ?? 1.0
                        switch type {
                        case "linear":
                            LinearKeyframe(scale, duration: duration)
                        case "spring":
                            let response = keyframe["response"] as? Double ?? 0.5
                            let dampingRatio = keyframe["dampingRatio"] as? Double ?? 1.0
                            SpringKeyframe(scale, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                        case "cubic":
                            let startVelocity = keyframe["startVelocity"] as? Double
                            let endVelocity = keyframe["endVelocity"] as? Double
                            CubicKeyframe(scale, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                        default:
                            LinearKeyframe(scale, duration: 1.0)
                        }
                    }
                }
                KeyframeTrack(\AnimationValues.rotation) {
                    for (time, keyframe) in keyframeValues {
                        let type = keyframe["type"] as? String ?? "linear"
                        let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                        let rotation = valueDict["rotation"] as? Double ?? 0.0
                        let duration = keyframe["duration"] as? Double ?? 1.0
                        switch type {
                        case "linear":
                            LinearKeyframe(rotation, duration: duration)
                        case "spring":
                            let response = keyframe["response"] as? Double ?? 0.5
                            let dampingRatio = keyframe["dampingRatio"] as? Double ?? 1.0
                            SpringKeyframe(rotation, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                        case "cubic":
                            let startVelocity = keyframe["startVelocity"] as? Double
                            let endVelocity = keyframe["endVelocity"] as? Double
                            CubicKeyframe(rotation, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                        default:
                            LinearKeyframe(rotation, duration: 1.0)
                        }
                    }
                }
            }
            
            // Handle repeat logic by monitoring animation completion
            view = view.onChange(of: animationTrigger) { _, newValue in
                if newValue > 0, let count = repeatCount, currentRepeatCount < count {
                    currentRepeatCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                        if autoreverses && currentRepeatCount < count {
                            animationTrigger = 0 // Reverse animation
                            currentRepeatCount += 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                                if currentRepeatCount < count {
                                    animationTrigger += 1 // Forward again
                                }
                            }
                        } else if currentRepeatCount < count {
                            animationTrigger += 1 // Continue forward
                        }
                    }
                }
            }
            
            // Conditionally apply modifiers based on trigger
            if trigger == "onAppear" {
                view = view.onAppear {
                    startAnimation()
                    handleAction()
                }
            } else if trigger == "onTap" {
                view = view.onTapGesture {
                    startAnimation()
                    handleAction()
                }
            } else if trigger == "onTimer" {
                view = view.onReceive(Timer.publish(every: timerInterval, on: .main, in: .common).autoconnect()) { _ in
                    startAnimation()
                    handleAction()
                }
            } else if trigger == "onStateChange" {
                view = view.onChange(of: (state.wrappedValue[0] as? [String: Any])?[stateKey] as? Int, initial: false) { _, newValue in
                    if let newValue = newValue {
                        // Update state
                        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                        newState["value"] = newValue
                        newState["validatedProperties"] = properties
                        state.wrappedValue[element.id] = newState
                        
                        animationTrigger = newValue
                        handleAction()
                    }
                }
            }
            
            return view
        } else {
            print("Warning: KeyframeAnimator requires iOS 17.0 or macOS 14.0; returning EmptyView")
            return SwiftUI.EmptyView()
        }
    }
        
    // Helper to parse percentage strings (e.g., "0%" -> 0.0, "100%" -> 1.0)
    private static func parsePercent(_ percent: String) -> Double {
        let cleaned = percent.replacingOccurrences(of: "%", with: "")
        return (Double(cleaned) ?? 0.0) / 100.0
    }
}
