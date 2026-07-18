# Body Metrics / BMI (ActionUI Example - Level 1 of 5)

**Complexity:** Level 1 / 5 (difficulty score 1.5).
**Previous:** [Temperature Converter](../TemperatureConverter/) (Level 1, score 1.0) - the canonical first applet.
**Next:** [Pocket Calculator](../PocketCalculator/) (Level 2) - a button grid driving a host-side state machine.

A tiny health-metrics app: two `Slider`s (height, weight) and a metric/imperial `Toggle` feed a live BMI readout. A circular `Gauge` tracks BMI across a 10-40 range, and BOTH the Gauge and the category `Text` recolor by health zone - blue/cyan underweight, green normal, orange overweight, red obese. Everything recomputes live on any input change. Defaults: ~170 cm / 70 kg (BMI 24.2, "Normal").

## What you learn

- The one loop every ActionUI app runs: **host loads the JSON -> registers handlers for the actionIDs the JSON fires -> reads inputs by id, computes, writes outputs by id.**
- That the *same* `shared/BodyMetrics.json` drives iOS/macOS (SwiftUI), Android (Compose), and Web (DOM) - only the thin host glue differs.
- The value bridge for non-text inputs: read a `Slider` (Double) and a `Toggle` (Bool), write a `Gauge` value and `Text` labels, all addressed by integer id.
- **Conditional color from data via `setElementProperty`**: `foregroundStyle` is a runtime-settable property on all three platforms, so the host pushes a named color ("cyan"/"green"/"orange"/"red") onto the Gauge and the category Text on every recompute. This is the same property MemeMaker and ColorStudio drive.

## Layout

```
BodyMetrics/
  shared/BodyMetrics.json     # the one UI skeleton, used by all hosts
  apple/   project.yml + generate_xcodeproj.sh + BodyMetricsApp.swift  (+ generated .xcodeproj)
  android/ Gradle project (settings/build + bodymetrics/, wrapper) -> bodymetrics/.../MainActivity.kt
  web/     index.html + app.js + two symlinks (actionui, BodyMetrics.json)
  package_web_app.sh          # emit a self-contained web build into out/
```

ActionUI JSON is strict JSON - **no comments allowed**. The teaching comments live in the host code; the JSON contract is the two tables below.

## Data contract (the JSON's ids)

The root is a single-screen `VStack` sized to fit a compact iPhone (title, Toggle, GroupBox of sliders, gauge cluster) - no `ScrollView`. Its `frame` carries `minWidth`/`minHeight` (the macOS window's resize floor), `idealWidth`/`idealHeight` (the opening size), and `maxWidth`/`maxHeight` infinity with top alignment so phone content pins under the safe area instead of floating in the middle. Slider values are always stored in metric (cm, kg); the toggle only changes how the read-out labels are formatted (ft/in, lb). BMI is unit-agnostic, computed from the metric values.

The gauge cluster is a fixed `ZStack` sized to the ring's visual diameter: accessory-circular intrinsic (~71) times `scaleEffect` 2.7, so the frame is 192 on every platform and does not rely on draw overflow past layout bounds. The category label (id 60) lives *inside* that `ZStack`, under the BMI caption, so it stays above the ring in z-order on every size class.

| id | element | host does |
|---|---|---|
| 10 | Toggle (imperial units) | **reads** the on/off Bool (default off = metric) |
| 20 | Slider height, 100-220 cm | **reads** the height in cm |
| 21 | Text height read-out | **writes** "170 cm" or "5 ft 7 in" |
| 30 | Slider weight, 30-200 kg | **reads** the weight in kg |
| 31 | Text weight read-out | **writes** "70 kg" or "154 lb" |
| 40 | Gauge BMI 10-40 | **writes** the (clamped) BMI value AND `foregroundStyle` + `tint` color |
| 50 | Text BMI numeric (selectable) | **writes** the BMI to one decimal |
| 60 | Text category (inside gauge ZStack) | **writes** the category name AND `foregroundStyle` color |

## Action table

| actionID | fired by | host does |
|---|---|---|
| `bmi.recompute` | id 10 `actionID`; id 20 and id 30 `valueChangeActionID` | read 10/20/30, compute BMI = kg / m^2, write the read-outs, the Gauge value + `foregroundStyle`/`tint`, the BMI number, and the category name + color |

One action id covers the whole screen: every input fires `bmi.recompute`, and the single handler re-reads all three inputs each time. That is the simplest correct pattern - no per-field bookkeeping.

The category mapping (and its color, pushed to id 60 as `foregroundStyle` and to id 40 as both `foregroundStyle` and `tint` - iOS `accessoryCircularCapacity` needs `tint` for the ring):

| BMI | category | color |
|---|---|---|
| < 18.5 | Underweight | cyan |
| 18.5 - 24.9 | Normal | green |
| 25.0 - 29.9 | Overweight | orange |
| >= 30.0 | Obese | red |

## Run it

### Web (turnkey, no build)

The `web/` folder references the framework and the UI through two symlinks
(`actionui -> ../../../ActionUIWeb`, `BodyMetrics.json -> ../shared/...`), so it
just works when served from the ActionUI repo root:

```
cd ${HOME}/git/ActionUI
python3 -m http.server 8080 --protocol HTTP/1.1
# then open http://localhost:8080/Examples/BodyMetrics/web/
```

To get a **self-contained, symlink-free** copy (for zipping/deploying), run
`./package_web_app.sh` - it resolves the symlinks and copies only the core
ActionUIWeb runtime into `out/BodyMetrics/`, which serves on its own.

### Apple (XcodeGen)

The Xcode project is described by `apple/project.yml` and generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `.xcodeproj` is
committed, so most people just open it and build - no XcodeGen needed. Only after
editing `project.yml` do you regenerate:

```
cd Examples/BodyMetrics/apple
brew install xcodegen   # one time
./generate_xcodeproj.sh # writes BodyMetrics.xcodeproj
open BodyMetrics.xcodeproj
```

The project depends on the ActionUI Swift package at the repo root (products
`ActionUI` + `ActionUISwiftAdapter`) and bundles `shared/BodyMetrics.json`. It
builds for **both iOS and macOS**: XcodeGen emits two schemes, `BodyMetrics_iOS`
(deployment target 17.6) and `BodyMetrics_macOS` (14.6) - pick one from the scheme
selector. The same `BodyMetricsApp.swift` host runs on both via the SwiftUI App
lifecycle.

### Android (Gradle - no project generator needed)

There is no XcodeGen analog for Android, and none is needed: **a Gradle project
*is* the project**. Android Studio opens the committed Gradle files directly, and
`./gradlew` builds from the command line - nothing to generate. The only special
part is wiring to the framework in the sibling repo dir, done once in
`settings.gradle.kts` as a Gradle **composite build** (`includeBuild` +
dependency substitution maps `com.abracode.actionui:library` to ActionUIAndroid's
`:library`, built from source).

```
# Android Studio: open Examples/BodyMetrics/android/
# or CLI:
cd Examples/BodyMetrics/android
./gradlew :bodymetrics:installDebug    # needs an Android SDK + a device/emulator
```

The shared JSON is single-sourced: `bodymetrics/build.gradle.kts` adds `../../shared`
as an extra assets directory (`sourceSets["main"].assets.srcDir("../../shared")`), so
the JSON in `shared/` is packaged directly - no copy step. First build also downloads
the Material Symbols font (~15 MB) via the library's own task, so the initial build
needs network.

## A cross-platform note (a "walk before run" payoff)

The headline feature here is **conditional color from data**, and it is identical in
shape on all three hosts: on every recompute the host calls `setElementProperty(id,
"foregroundStyle", colorName)` on the category Text and both `foregroundStyle` and
`tint` on the Gauge. `foregroundStyle` / `tint` are runtime-settable on Apple,
Android, and Web alike, so a tiny applet proves the data-driven-styling path
SharedCare needs for status coloring before the big app hits it.

## Build-status notes

All four targets are green as authored. The shared JSON validates against the ActionUI
verifier. **macOS** (`BodyMetrics_macOS`) and **iOS Simulator** (`BodyMetrics_iOS`, iPhone
17 Pro) both `BUILD SUCCEEDED` via `xcodebuild`. **Android** (`./gradlew assembleDebug
--offline`) produced `bodymetrics-debug.apk`. **Web** is served and packaged symlink-free
into `out/BodyMetrics/`. No shared engine/library code was changed.
