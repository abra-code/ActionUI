# ActionUI vs React Native

A comparison of ActionUI with React Native, focusing on architecture, philosophy, and trade-offs. ActionUI now drives **three native renderers from one JSON schema**: SwiftUI on Apple platforms (iOS, macOS, and the rest), Jetpack Compose on Android, and DOM/CSS in the browser. React Native additionally targets Windows and Linux through community-maintained forks. The two frameworks are now direct cross-platform competitors for iOS + Android + Web, with different architecture trade-offs.

## Architectural Differences

| Aspect | ActionUI | React Native |
|--------|----------|--------------|
| Runtime | None — Apple: JSON → SwiftUI directly; Android: JSON → Jetpack Compose; Web: JSON → DOM/CSS (plain ES modules, no build step) | JavaScript engine (Hermes/JSC) with native bridge |
| UI definition | Pure data (JSON) — same schema on all platforms | Code (JSX) that produces virtual DOM |
| Rendering | Apple: SwiftUI views directly; Android: Jetpack Compose views; Web: real DOM elements | Bridge to UIKit/AppKit/Android (New Architecture: Fabric) |
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
ActionUI produces actual native views with full platform behavior on every target — SwiftUI on Apple platforms, Jetpack Compose on Android, and real DOM/CSS in the browser. It doesn't abstract away the platform; it embraces each one. The same JSON key drives a `NavigationBar` on Android and a `TabView` on iOS without any client code change. Where platforms genuinely differ (e.g. a macOS-only Table or an Android-specific Material style), ActionUI lets JSON express that with a `:android` / `:ios` suffix rather than forcing a fake cross-platform abstraction.

Even the Web renderer avoids the usual abstraction tax: it emits plain DOM and CSS with no framework runtime, no virtual DOM, and no build step. React Native, by contrast, bridges to UIKit and Android's native views, and its Web target (React Native Web) re-implements native primitives on top of the DOM. The JS bridge means some platform behaviors are approximated or require manual native modules. macOS support is maintained by Microsoft (react-native-macos), not first-class.

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

### Zero-Dependency Web Renderer
ActionUI's browser renderer emits plain DOM and CSS from the same JSON that drives Apple and Android — no framework runtime, no virtual DOM, no bundler, no npm install. It is served as static ES modules straight from a URL ([live demo](https://abracode.com/ActionUIWeb/demo/)), works from any path prefix, and includes touch/mobile adaptation (bottom sheets, collapsing navigation, swipe-back, pull-to-refresh). React Native's browser story (React Native Web) re-implements native primitives on top of the DOM and still ships a JS bundle and build toolchain. For a lightweight embeddable UI on the web, ActionUI's output is dramatically smaller and simpler.

## Where React Native Excels

### Broader Platform Reach
Web is no longer a React Native advantage — ActionUI ships its own browser renderer (see "Zero-Dependency Web Renderer" above). What React Native still reaches that ActionUI does not is the desktop-Windows and Linux surface, via the community-maintained react-native-windows and react-native-linux forks. For apps that must run natively on Windows or Linux, React Native remains the practical choice; ActionUI's non-Apple desktop story is the browser.

### Ecosystem Maturity on Android
Both frameworks now cover iOS, Android, and Web. React Native's Android ecosystem is older and deeper — more battle-tested third-party libraries, more Stack Overflow answers, more edge cases already hit and fixed. ActionUI's Android renderer (Jetpack Compose) reached feature parity with the Apple renderer this release, sharing the same JSON across all three platforms, but it is younger and its community is smaller. A handful of add-on element types (e.g. the Chat element) are Apple-only for now. For apps within the shared element set, the JSON is identical across platforms with no code changes.

### Dynamic UI Construction
React Native's core model is dynamic — every render cycle can produce a completely different component tree based on state. Conditional rendering, lists of dynamic length, and component composition are natural.

ActionUI's UI structure is defined by JSON at window creation. Dynamic behavior comes from property changes (isHidden, items, values) and LoadableView for swapping sections. This covers most practical needs but isn't as flexible as arbitrary component trees.

### Ecosystem
React Native has thousands of third-party components, navigation libraries (React Navigation, Expo Router), animation libraries (Reanimated), and form libraries. The npm ecosystem provides solutions for most common needs.

ActionUI is a focused library without a third-party ecosystem. Its ~57 built-in components cover common UI patterns, and a new add-on architecture lets custom element types (Chat, Diff, RichText, QuickLook, CachedImage) register into the engine without living in core — but specialized needs still require extending the framework rather than reaching for an existing package.

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
| Lightweight web UI with no build step or JS bundle | ActionUI |
| Native Windows / Linux desktop | React Native |
| Deep/mature Android third-party ecosystem | React Native |
| AI-generated UIs | ActionUI |
| Complex animations and gesture-driven interactions | React Native |
| Native macOS integration (menus, panels, multi-window) | ActionUI |
| Large team with JS/TS expertise | React Native |
| Minimal toolchain and dependencies | ActionUI |
| Third-party component ecosystem | React Native |
| Language-agnostic client code (Python, C, Swift, C++) | ActionUI |
| Same JSON drives Apple, Android, and the Web | ActionUI |
