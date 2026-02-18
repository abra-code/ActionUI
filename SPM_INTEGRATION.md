# ActionUI — Swift Package Manager Integration Guide

This document explains how to add ActionUI to your project via SPM and describes the
package structure and product choices.

---

## Quick Start — Adding ActionUI as a Dependency

### In an Xcode project

1. **File -> Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/abra-code/ActionUI
   ```
3. Select the version rule (e.g. `Up to Next Major`) and click **Add Package**.
4. In the *Choose Package Products* sheet, tick the product(s) you need (see below).

### In another `Package.swift`

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/abra-code/ActionUI", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ActionUISwiftAdapter", package: "ActionUI"),
        ]
    ),
]
```

---

## Products / What to Import

| Product | Import | Use when |
|---|---|---|
| `ActionUI` | `import ActionUI` | You need direct access to `ActionUIModel`, `ActionUIRegistry`, view protocols, etc. |
| `ActionUISwiftAdapter` | `import ActionUISwiftAdapter` | You want the simplified `ActionUISwift` static API (recommended for most Swift apps). |
| `ActionUICAdapter` | *(include C headers)* | Your integration layer is written in C. |
| `ActionUIObjCAdapter` | `@import ActionUIObjCAdapter;` | Your codebase is Objective-C or mixed. |
| `ActionUIJavaScriptCoreAdapter` | `import ActionUIJavaScriptCoreAdapter` | You drive UI from a `JSContext` (e.g. automation scripts). |
| `ActionUIWebKitJSAdapter` | `import ActionUIWebKitJSAdapter` | You use `WKWebView` and want to call ActionUI from JavaScript. |

> **Not included:** `ActionUICppAdapter` is excluded from this distribution.

---

## Platform Support

| Platform | Minimum version |
|---|---|
| macOS | 14.6 |
| iOS / iPadOS | 17.6 |
| tvOS | 17.6 |
| watchOS | 10.6 |
| visionOS | 2.6 |

