---
id: swiftui-alignment
level: 1
flavors: [claude, capable]
---

## SwiftUI Alignment

ActionUI property names and values **exactly match SwiftUI modifier names**. If you know SwiftUI, you already know ActionUI: `foregroundStyle`, `font`, `padding`, `frame`, `clipShape`, `cornerRadius`, `shadow`, `rotationEffect`, `scaleEffect`, `animation` — all spelled and valued the same way as their SwiftUI counterparts.

The JSON tree mirrors the SwiftUI view hierarchy. Container views (`VStack`, `HStack`, `List`, `NavigationStack`) correspond directly to their SwiftUI equivalents. Modifier application order follows SwiftUI conventions.

When in doubt about a property name or value, ask: "what does SwiftUI call this?" — the answer is the ActionUI property name.
