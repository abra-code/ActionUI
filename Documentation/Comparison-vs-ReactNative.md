# ActionUI vs React Native

A comparison of ActionUI with React Native, focusing on architecture, philosophy, and trade-offs — setting aside the obvious difference that ActionUI targets only Apple platforms while React Native is cross-platform (iOS, Android, Web).

## Architectural Differences

| Aspect | ActionUI | React Native |
|--------|----------|--------------|
| Runtime | None — JSON parsed directly into SwiftUI | JavaScript engine (Hermes/JSC) with native bridge |
| UI definition | Pure data (JSON) | Code (JSX) that produces virtual DOM |
| Rendering | SwiftUI views directly | Bridge to UIKit/AppKit (New Architecture: Fabric) |
| State | Flat set/get by view ID | useState, useReducer, Redux, Context API, etc. |
| Diffing | None — SwiftUI handles updates | Virtual DOM reconciliation |
| Build toolchain | Xcode, static frameworks | Node.js, Metro bundler, Babel/TypeScript, CocoaPods/Gradle |
| Client language | Any (Python, C, Swift, ObjC, JS, C++) | JavaScript/TypeScript |

## Where ActionUI Excels

### Simplicity
ActionUI has no runtime, no virtual DOM, no reconciliation, no bridge. JSON goes in, SwiftUI views come out. State changes call `set_value()` and SwiftUI handles the rest. There is no state management framework to choose, no component lifecycle to manage, no hooks to understand.

React Native requires understanding JSX, component lifecycle, hooks (useState, useEffect, useMemo, useCallback), the bridge architecture, and typically a state management library. The mental model is significantly more complex.

### True Native SwiftUI
ActionUI produces actual SwiftUI views with full modifier support. It doesn't abstract away the platform — it embraces it. NavigationSplitView, Table, Gauge, Map, DisclosureGroup, and 50+ other components are real SwiftUI views with native behavior.

React Native bridges to UIKit (and AppKit via third-party support). The views are native but the abstraction layer means some platform behaviors are lost or approximated. macOS support is a community effort (react-native-macos), not first-class.

### macOS-First
ActionUI has deep AppKit integration: native menu bars with CommandGroup/CommandMenu, file open/save panels, alert dialogs, multi-window with per-window state, window lifecycle callbacks. This is first-class macOS app behavior.

React Native's macOS support is maintained by Microsoft (react-native-macos) and lacks many macOS conventions — proper menu bars, multi-window, and native panels require significant custom native code.

### Build Toolchain
ActionUI: one Xcode project, `pip install` for the Python bridge. No node_modules, no Metro bundler, no Babel, no TypeScript transpiler, no CocoaPods/Gradle version matrix.

A fresh React Native project pulls hundreds of npm dependencies and requires coordinating versions across the JS and native toolchains. Build issues from version mismatches are common.

### Performance
ActionUI has essentially zero overhead — calling SwiftUI is the entire rendering path. No JS-to-native bridge, no serialization, no virtual DOM diffing.

React Native's bridge adds latency to every interaction that crosses the JS/native boundary. The New Architecture (JSI, Fabric, TurboModules) reduces this but adds its own complexity.

### Language Agnostic
ActionUI's C API means any language that can call C functions can drive the UI: Python, Swift, Objective-C, C++, JavaScript (via JavaScriptCore or WebKit). The UI definition (JSON) is completely separate from the client language.

React Native locks you into JavaScript/TypeScript for app logic.

### Dynamic UI Loading
LoadableView loads new JSON UI definitions at runtime from local files or network URLs. This is a production feature — deployed apps can reconfigure their UI dynamically. This is comparable to React Native's hot reload but available in shipping apps, not just during development.

## Where React Native Excels

### Cross-Platform
React Native targets iOS, Android, and Web from a single codebase. ActionUI is Apple-only. For apps that must run on Android, React Native (or similar cross-platform frameworks) is the practical choice.

### Dynamic UI Construction
React Native's core model is dynamic — every render cycle can produce a completely different component tree based on state. Conditional rendering, lists of dynamic length, and component composition are natural.

ActionUI's UI structure is defined by JSON at window creation. Dynamic behavior comes from property changes (isHidden, items, values) and LoadableView for swapping sections. This covers most practical needs but isn't as flexible as arbitrary component trees.

### Ecosystem
React Native has thousands of third-party components, navigation libraries (React Navigation, Expo Router), animation libraries (Reanimated), and form libraries. The npm ecosystem provides solutions for most common needs.

ActionUI is a focused library without a third-party ecosystem. Its 50+ built-in components cover common UI patterns, but specialized needs require extending the framework.

### Navigation and Routing
React Native has mature navigation solutions with stack navigators, tab navigators, drawer navigators, deep linking, and animated transitions.

ActionUI has NavigationStack, NavigationSplitView, and TabView in JSON, but complex navigation flows with animated transitions between screens are not its primary use case.

### Animations
React Native offers the Animated API and Reanimated library for complex, gesture-driven animations running on the native thread.

ActionUI inherits SwiftUI's built-in animations (which are excellent) but doesn't expose a programmatic animation API from the client side.

### Hot Reload (Development)
React Native's Fast Refresh updates the running app as you edit JS source code, preserving component state. It's a developer tool that significantly speeds up iteration.

ActionUI's iteration cycle is: edit JSON, close window, reopen. No compilation step for UI changes, so the turnaround is fast, but it's not automatic. (A debug reload feature is under consideration.)

## Philosophical Difference

React Native is a **full application framework** — it wants to own the entire app, from navigation to state to rendering. It's designed for large consumer apps with complex interaction patterns.

ActionUI is a **UI rendering service** — it presents views and reports actions, staying out of the way of app logic. The client (Python, Swift, etc.) handles everything else. It's designed for tools, utilities, and applets where the UI is a means to an end, not the product itself.

This is not a limitation — it's a deliberate design choice. For applet-style apps, ActionUI's thin layer is an advantage: less to learn, less to debug, less that can go wrong. The right tool depends on the scope of what you're building.

## Summary

| For this need... | Better choice |
|------------------|---------------|
| macOS applets and tools | ActionUI |
| Cross-platform consumer apps | React Native |
| AI-generated UIs | ActionUI |
| Complex navigation flows | React Native |
| Native macOS integration (menus, panels, multi-window) | ActionUI |
| Large team with JS/TS expertise | React Native |
| Minimal toolchain and dependencies | ActionUI |
| Third-party component ecosystem | React Native |
| Language-agnostic client code | ActionUI |
| Rapid prototyping on Apple platforms | ActionUI |
