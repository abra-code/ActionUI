// Sources/Views/KeyframeAnimator.swift
/*
 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "initialValue": { "opacity": 0.0, "scale": 1.0, "rotation": 0.0 },
     "trigger": "onAppear", // "onAppear", "onTap", "onTimer", "onStateChange"
     "timerInterval": 2.0, // Optional, for onTimer
     "stateKey": "counter", // Optional, for onStateChange
     "repeat": { "count": 3, "autoreverses": true }, // Optional
     "delay": 1.0, // Optional
     "keyframes": {
       "0%": { "type": "linear", "value": { "opacity": 0.0, "scale": 0.5 }, "duration": 0.8 },
       "50%": { "type": "spring", "value": { "opacity": 1.0, "scale": 1.5 }, "duration": 0.5, "response": 0.4, "dampingRatio": 0.6 },
       "100%": { "type": "cubic", "value": { "opacity": 0.5, "scale": 1.0 }, "duration": 0.6, "startVelocity": 0.2, "endVelocity": 0.4 },
       "25%": { "type": "spring", "value": { "opacity": 0.5 }, "duration": 0.4, "response": 0.5, "dampingRatio": 1.0 }
     }
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
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, _ in
        return properties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ViewElement(id: ViewElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let initialValue = (properties["initialValue"] as? [String: Any]).map {
            AnimationValues(
                opacity: $0.double(forKey: "opacity") ?? 1.0,
                scale: $0.double(forKey: "scale") ?? 1.0,
                rotation: $0.double(forKey: "rotation") ?? 0.0
            )
        } ?? AnimationValues()
        let trigger = (properties["trigger"] as? String) ?? "onAppear"
        let timerInterval = (properties.double(forKey: "timerInterval")) ?? 1.0
        let stateKey = (properties["stateKey"] as? String) ?? "counter"
        let repeatDict = properties["repeat"] as? [String: Any]
        let count = (repeatDict?["count"] as? Int) ?? 1
        let autoreverses = (repeatDict?["autoreverses"] as? Bool) ?? false
        let delay = (properties.double(forKey: "delay")) ?? 0.0
        let keyframes = (properties["keyframes"] as? [String: [String: Any]]) ?? [:]
        
        @State var animationTrigger: Int = 0
        @State var currentRepeatCount: Int = 0
        
        // Helper to start animation
        func startAnimation() {
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation {
                        animationTrigger += 1
                    }
                }
            } else {
                withAnimation {
                    animationTrigger += 1
                }
            }
        }
        
        // Initialize state
        // TODO: must not mutate model in buildView
        model.states["currentRepeatCount"] = currentRepeatCount
        
        return SwiftUI.KeyframeAnimator(
            initialValue: initialValue,
            trigger: animationTrigger
        ) { contentValue in
            let windowModel = ActionUIModel.shared.windowModels[windowUUID]
            if let childModel = windowModel?.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
                    .opacity(contentValue.opacity)
                    .scaleEffect(contentValue.scale)
                    .rotationEffect(.degrees(contentValue.rotation))
            }
        } keyframes: { _ in
            KeyframeTrack(\AnimationValues.opacity) {
                for (percent, keyframe) in keyframes.sorted(by: { Self.parsePercent($0.key) < Self.parsePercent($1.key) }) {
                    let type = keyframe["type"] as? String ?? "linear"
                    let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                    let opacity = valueDict.double(forKey: "opacity") ?? initialValue.opacity
                    let duration = keyframe.double(forKey: "duration") ?? 0.5
                    
                    switch type {
                    case "spring":
                        let response = keyframe.double(forKey: "response") ?? 0.5
                        let dampingRatio = keyframe.double(forKey: "dampingRatio") ?? 1.0
                        SpringKeyframe(opacity, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                    case "cubic":
                        let startVelocity = keyframe.double(forKey: "startVelocity") ?? 0.0
                        let endVelocity = keyframe.double(forKey: "endVelocity") ?? 0.0
                        CubicKeyframe(opacity, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                    default:
                        LinearKeyframe(opacity, duration: duration)
                    }
                }
            }
            KeyframeTrack(\AnimationValues.scale) {
                for (percent, keyframe) in keyframes.sorted(by: { Self.parsePercent($0.key) < Self.parsePercent($1.key) }) {
                    let type = keyframe["type"] as? String ?? "linear"
                    let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                    let scale = valueDict.double(forKey: "scale") ?? initialValue.scale
                    let duration = keyframe.double(forKey: "duration") ?? 0.5
                    
                    switch type {
                    case "spring":
                        let response = keyframe.double(forKey: "response") ?? 0.5
                        let dampingRatio = keyframe.double(forKey: "dampingRatio") ?? 1.0
                        SpringKeyframe(scale, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                    case "cubic":
                        let startVelocity = keyframe.double(forKey: "startVelocity") ?? 0.0
                        let endVelocity = keyframe.double(forKey: "endVelocity") ?? 0.0
                        CubicKeyframe(scale, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                    default:
                        LinearKeyframe(scale, duration: duration)
                    }
                }
            }
            KeyframeTrack(\AnimationValues.rotation) {
                for (percent, keyframe) in keyframes.sorted(by: { Self.parsePercent($0.key) < Self.parsePercent($1.key) }) {
                    let type = keyframe["type"] as? String ?? "linear"
                    let valueDict = keyframe["value"] as? [String: Any] ?? [:]
                    let rotation = valueDict.double(forKey: "rotation") ?? initialValue.rotation
                    let duration = keyframe.double(forKey: "duration") ?? 0.5
                    
                    switch type {
                    case "spring":
                        let response = keyframe.double(forKey: "response") ?? 0.5
                        let dampingRatio = keyframe.double(forKey: "dampingRatio") ?? 1.0
                        SpringKeyframe(rotation, duration: duration, spring: .init(response: response, dampingRatio: dampingRatio))
                    case "cubic":
                        let startVelocity = keyframe.double(forKey: "startVelocity") ?? 0.0
                        let endVelocity = keyframe.double(forKey: "endVelocity") ?? 0.0
                        CubicKeyframe(rotation, duration: duration, startVelocity: startVelocity, endVelocity: endVelocity)
                    default:
                        LinearKeyframe(rotation, duration: duration)
                    }
                }
            }
        }
        .onChange(of: animationTrigger) { _, newValue in
            if autoreverses && currentRepeatCount < count {
                if newValue % 2 == 0 {
                    currentRepeatCount += 1
                    startAnimation()
                }
            } else if currentRepeatCount < count {
                currentRepeatCount += 1
                startAnimation()
            }
            model.states["currentRepeatCount"] = currentRepeatCount
        }
        .onAppear {
            if trigger == "onAppear" {
                startAnimation()
            }
        }
        .onTapGesture {
            if trigger == "onTap" {
                startAnimation()
            }
        }
        .onReceive(Timer.publish(every: timerInterval, on: .main, in: .common).autoconnect()) { _ in
            if trigger == "onTimer" {
                startAnimation()
            }
        }
        .onChange(of: model.states[stateKey] as? Int, initial: false) { _, newValue in
            if trigger == "onStateChange", let newValue = newValue {
                animationTrigger = newValue
                model.value = newValue
            }
        }
    }
    
    // Helper to parse percentage strings (e.g., "0%" -> 0.0, "100%" -> 1.0)
    private static func parsePercent(_ percent: String) -> Double {
        let cleaned = percent.replacingOccurrences(of: "%", with: "")
        return (Double(cleaned) ?? 0.0) / 100.0
    }
}
