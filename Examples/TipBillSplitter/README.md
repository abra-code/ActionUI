# Tip & Bill Splitter (ActionUI Example - the non-SwiftUI host)

The same one-screen ActionUI app pattern as the other examples, but with a
**distinctive Apple host**: on Apple this app's foundation is **AppKit (macOS)**
and **UIKit (iOS)** - *not* the SwiftUI `App` lifecycle. ActionUI still renders
SwiftUI views; we drop the rendered tree into a classic `NSWindow` /
`UIViewController` shell. That is the whole point of this app: proving ActionUI
hosts cleanly in a non-SwiftUI app.

It splits a restaurant bill: type the bill amount, drag the tip slider, step the
party size, and the tip, total, and per-person figures recompute live.

## What you learn

- The one loop every ActionUI app runs: **host loads the JSON -> registers
  handlers for the actionIDs the JSON fires -> reads inputs by id, computes,
  writes outputs by id.**
- That the *same* `shared/TipBillSplitter.json` drives iOS/macOS (SwiftUI),
  Android (Compose), and Web (DOM) - only the thin host glue differs.
- **Hosting ActionUI from a non-SwiftUI app shell**: the macOS target is an
  `NSApplication` + `AppDelegate` + `NSWindow` hosting an `NSHostingController`;
  the iOS target is `UIApplicationMain` + `AppDelegate` + `SceneDelegate` +
  `UIViewController` embedding a `UIHostingController`. Compare with the other
  examples, which use the SwiftUI `App` lifecycle.
- The value bridge across three input element types: read a currency `TextField`,
  a `Slider`, and a `Stepper`; write four `Text`s, all by integer id.
- `valueChangeActionID` vs `actionID`: `TextField` and `Slider` fire
  `valueChangeActionID` on every change; `Stepper` fires `actionID` on each step.

## Layout

```
TipBillSplitter/
  shared/TipBillSplitter.json          # the one UI skeleton, used by all hosts
  apple/   project.yml + generate_xcodeproj.sh + the AppKit/UIKit Swift hosts  (+ generated .xcodeproj)
           AppKitMain.swift            # macOS: NSApplication + AppDelegate + NSWindow + NSHostingController
           UIKitAppDelegate.swift      # iOS:  UIApplicationMain + AppDelegate
           UIKitSceneDelegate.swift    # iOS:  SceneDelegate + UIViewController + UIHostingController
           TipLogic.swift              # the recompute, shared by both Apple shells
           Info-iOS.plist              # iOS scene manifest (module-qualified SceneDelegate)
  android/ Gradle project (settings/build + tipbillsplitter/, wrapper) -> MainActivity.kt
  web/     index.html + app.js + two symlinks (actionui, TipBillSplitter.json)
  package_web_app.sh                   # emit a self-contained web build into out/
```

ActionUI JSON is strict JSON - **no comments allowed**. The teaching comments live
in the host code; the JSON contract is the two tables below.

## Data contract (the JSON's ids)

The root is a chrome-less `VStack` (no `NavigationStack`). Its `frame` carries
`minWidth`/`minHeight` (the macOS window's resize floor) and `idealWidth`/
`idealHeight` (the opening size). Only the interactive and host-written elements
carry ids; the containers and static labels do not.

| id | element | host does |
|---|---|---|
| 10 | TextField (currency, USD) | **reads** the bill amount (strips `$`/commas, parses) |
| 20 | Slider (0-30, step 1) | **reads** the tip percentage (Double) |
| 30 | Stepper (1-20, step 1) | **reads** the party size (Double, guarded `>= 1`) |
| 40 | Text | **writes** the tip amount, `$0.00` |
| 50 | Text | **writes** the total, `$0.00` |
| 60 | Text | **writes** the per-person amount, `$0.00` |
| 80 | Text | **writes** the slider read-out, `Tip: N%` |

## Action table

| actionID | fired by | host does |
|---|---|---|
| `tip.recompute` | id 10 + id 20 `valueChangeActionID`; id 30 `actionID` | read 10/20/30, compute tip/total/per-person, write 40/50/60 and the read-out label 80 |

One action id covers the whole screen: every input fires `tip.recompute`, and the
single handler re-reads all three inputs each time. That is the simplest correct
pattern - no per-field bookkeeping. The math: `tip = bill * pct / 100`,
`total = bill + tip`, `perPerson = total / max(1, people)`; outputs are formatted
as currency with 2 decimals.

## Run it

### Web (turnkey, no build)

The `web/` folder references the framework and the UI through two symlinks
(`actionui -> ../../../ActionUIWeb`, `TipBillSplitter.json -> ../shared/...`), so it
just works when served from the ActionUI repo root:

```
cd /Users/tkukielk/git/ActionUI
python3 -m http.server 8080 --protocol HTTP/1.1
# then open http://localhost:8080/Examples/TipBillSplitter/web/
```

To get a **self-contained, symlink-free** copy (for zipping/deploying), run
`./package_web_app.sh` - it resolves the symlinks and copies only the core
ActionUIWeb runtime into `out/TipBillSplitter/`, which serves on its own.

### Apple (XcodeGen) - two distinct hosts, one shared logic

The Xcode project is described by `apple/project.yml` and generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `.xcodeproj` is
committed, so most people just open it and build. Only after editing `project.yml`
do you regenerate:

```
cd Examples/TipBillSplitter/apple
brew install xcodegen   # one time
./generate_xcodeproj.sh # writes TipBillSplitter.xcodeproj
open TipBillSplitter.xcodeproj
```

Unlike the other examples (one source set producing both platforms), this project
has **two separate targets with two separate source sets**, because the app shells
differ:

- `TipBillSplitter_macOS` (deployment target 14.6) - **AppKit**. `AppKitMain.swift`
  brings up `NSApplication` itself (`@main` struct calling `NSApplicationMain`),
  builds a code-only menu bar, creates an `NSWindow`, and sets its
  `contentViewController` to the `NSHostingController` returned by
  `ActionUISwift.loadHostingController(...)`. Note `window.isReleasedWhenClosed =
  false`: because the `AppDelegate` retains the window, the default `true` would
  SIGSEGV on close.
- `TipBillSplitter_iOS` (deployment target 17.6) - **UIKit**.
  `UIKitAppDelegate.swift` is the `@main` `UIApplicationDelegate`;
  `UIKitSceneDelegate.swift` builds a `UIWindow`, embeds the `UIHostingController`
  inside a plain `UIViewController` (the `addChild` / `addSubview` / `didMove`
  dance), and makes it the root. `Info-iOS.plist` carries the scene manifest with
  `UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).UIKitSceneDelegate` - a Swift
  host must module-qualify the delegate class name.

Both targets depend on the ActionUI Swift package at the repo root (products
`ActionUI` + `ActionUISwiftAdapter`), bundle `shared/TipBillSplitter.json`, and
route `tip.recompute` into the same `TipBillSplitter.recompute(_:)` in
`TipLogic.swift`. Pick a scheme from the selector. (Simulator + macOS need no code
signing; an iOS device build needs a signing team.)

### Android (Gradle - no project generator needed)

A Gradle project *is* the project - Android Studio opens the committed Gradle files
directly, and `./gradlew` builds from the CLI. The framework in the sibling repo dir
is wired once in `settings.gradle.kts` as a Gradle **composite build** (`includeBuild`
+ dependency substitution maps `com.abracode.actionui:library` to ActionUIAndroid's
`:library`, built from source).

```
# Android Studio: open Examples/TipBillSplitter/android/
# or CLI:
cd Examples/TipBillSplitter/android
./gradlew :tipbillsplitter:assembleDebug          # builds the debug APK
./gradlew :tipbillsplitter:installDebug           # needs an SDK + a device/emulator
```

The shared JSON is single-sourced: `tipbillsplitter/build.gradle.kts` adds
`../../shared` as an extra assets directory
(`sourceSets["main"].assets.srcDir("../../shared")`), so the JSON in `shared/` is
packaged directly - no copy step. First build also downloads the Material Symbols
font (~15 MB) via the library's own task, so the initial build needs network.

## Build status

All four targets were built and verified in the authoring environment:

- **macOS (AppKit)**: `xcodebuild` `-destination 'platform=macOS'` -> **BUILD SUCCEEDED**.
- **iOS (UIKit)**: `xcodebuild` `-destination 'generic/platform=iOS Simulator'` -> **BUILD SUCCEEDED**.
- **Android**: `./gradlew :tipbillsplitter:assembleDebug` -> **BUILD SUCCESSFUL** (APK produced).
- **Web**: served (all assets 200) and smoke-tested against the real shared JSON
  through the ActionUIWeb runtime - the recompute produced the correct
  tip/total/per-person currency and honored the `people >= 1` guard.

The shared JSON validates clean against the ActionUI verifier (0 errors).
