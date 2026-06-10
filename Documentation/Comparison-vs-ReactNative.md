# ActionUI vs React Native

A comparison of ActionUI with React Native, focusing on architecture, philosophy, and trade-offs. ActionUI targets iOS, macOS, and Android (the Android renderer uses Jetpack Compose and shares the same JSON schema). React Native additionally targets Web and has broader community-maintained platform coverage (Windows, Linux). The two frameworks are now direct cross-platform competitors for iOS + Android mobile, with different architecture trade-offs.

## Architectural Differences

| Aspect | ActionUI | React Native |
|--------|----------|--------------|
| Runtime | None — iOS/macOS: JSON → SwiftUI directly; Android: JSON → Jetpack Compose renderer | JavaScript engine (Hermes/JSC) with native bridge |
| UI definition | Pure data (JSON) — same schema on all platforms | Code (JSX) that produces virtual DOM |
| Rendering | iOS/macOS: SwiftUI views directly; Android: Jetpack Compose views | Bridge to UIKit/AppKit/Android (New Architecture: Fabric) |
| Cross-platform keys | `:android` / `:ios` suffix for per-platform overrides (rare) | `Platform.select()`, platform-specific file extensions |
| State | Flat set/get by view ID | useState, useReducer, Redux, Context API, etc. |
| Diffing | None — SwiftUI/Compose handles updates | Virtual DOM reconciliation |
| Build toolchain | Xcode + Swift (iOS/macOS), Android Studio + Gradle (Android) | Node.js, Metro bundler, Babel/TypeScript, CocoaPods/Gradle |
| Client language | Any (Python, C, Swift, ObjC, JS, C++) | JavaScript/TypeScript |

## Where ActionUI Excels

### Simplicity
ActionUI has no runtime, no virtual DOM, no reconciliation, no bridge. JSON goes in, SwiftUI views come out. State changes call `set_value()` and SwiftUI handles the rest. There is no state management framework to choose, no component lifecycle to manage, no hooks to understand.

React Native requires understanding JSX, component lifecycle, hooks (useState, useEffect, useMemo, useCallback), the bridge architecture, and typically a state management library. The mental model is significantly more complex.

### True Native Rendering
ActionUI produces actual native views with full platform behavior on every target — SwiftUI on iOS and macOS, Jetpack Compose on Android. It doesn't abstract away the platform; it embraces each one. The same JSON key drives a `NavigationBar` on Android and a `TabView` on iOS without any client code change. Where platforms genuinely differ (e.g. a macOS-only Table or an Android-specific Material style), ActionUI lets JSON express that with a `:android` / `:ios` suffix rather than forcing a fake cross-platform abstraction.

React Native bridges to UIKit and Android's native views. The views are native but the JS bridge means some platform behaviors are approximated or require manual native modules. macOS support is maintained by Microsoft (react-native-macos), not first-class.

### macOS-First
ActionUI has deep AppKit integration: native menu bars with CommandGroup/CommandMenu, file open/save panels, alert dialogs, multi-window with per-window state, window lifecycle callbacks. This is first-class macOS app behavior.

React Native's macOS support is maintained by Microsoft (react-native-macos) and lacks many macOS conventions — proper menu bars, multi-window, and native panels require significant custom native code.

### Build Toolchain
ActionUI: Xcode for iOS/macOS, Android Studio for Android, `pip install` for the Python bridge. No Node.js, no Metro bundler, no Babel, no TypeScript transpiler. Each platform uses its own standard native toolchain — nothing extra.

A React Native project adds a JavaScript layer on top of both native toolchains: hundreds of npm dependencies, Metro bundler, and Babel/TypeScript coordinated with CocoaPods and Gradle versions. Build failures from npm/native version mismatches are a common time cost.

### Performance
ActionUI has essentially zero overhead — calling SwiftUI is the entire rendering path. No JS-to-native bridge, no serialization, no virtual DOM diffing.

React Native's bridge adds latency to every interaction that crosses the JS/native boundary. The New Architecture (JSI, Fabric, TurboModules) reduces this but adds its own complexity.

### Language Agnostic
ActionUI's C API means any language that can call C functions can drive the UI: Python, Swift, Objective-C, C++, JavaScript (via JavaScriptCore or WebKit). The UI definition (JSON) is completely separate from the client language.

React Native locks you into JavaScript/TypeScript for app logic.

### Dynamic UI Loading
LoadableView loads new JSON UI definitions at runtime from local files or network URLs. This is a production feature — deployed apps can reconfigure their UI dynamically. This is comparable to React Native's hot reload but available in shipping apps, not just during development.

## Where React Native Excels

### Web Support
React Native (via React Native Web) and Expo can target browsers in addition to iOS and Android. ActionUI has no web renderer. For apps that must run in a browser, React Native is the practical choice.

### More Mature Android Coverage
Both frameworks target iOS and Android. React Native's Android support is well-established and covers the full component surface. ActionUI's Android renderer (Jetpack Compose) is in active development: 52 of 64 element types are ported, with the full navigation stack, modals (window- and element-level), dialogs, dynamic loading, an embedded WebView, and async images working. Some elements (Gauge, Grid, Canvas, Map, VideoPlayer) and some modifiers (animation system, element-level popover) are not yet ported. For apps that can work within the current element coverage, the JSON is the same — no code changes between platforms.

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
| iOS + Android with no JS runtime | ActionUI |
| Web support required | React Native |
| Full Android component coverage today | React Native |
| AI-generated UIs | ActionUI |
| Complex animations and gesture-driven interactions | React Native |
| Native macOS integration (menus, panels, multi-window) | ActionUI |
| Large team with JS/TS expertise | React Native |
| Minimal toolchain and dependencies | ActionUI |
| Third-party component ecosystem | React Native |
| Language-agnostic client code (Python, C, Swift, C++) | ActionUI |
| Same JSON drives iOS, macOS, and Android | ActionUI |
