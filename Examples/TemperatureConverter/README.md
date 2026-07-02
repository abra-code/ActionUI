# Temperature Converter (ActionUI Example - Level 1 of 5)

**Complexity:** Level 1 / 5 (difficulty score 1.0 - the canonical first applet).
**Previous:** none - start here.
**Next:** [Pocket Calculator](../PocketCalculator/) (Level 2) - a button grid driving a host-side state machine. *(planned)*

The smallest real ActionUI app: one JSON screen plus a thin native host per platform. It converts a number between Celsius, Fahrenheit, and Kelvin, recomputing live as you type or change a unit.

## What you learn

- The one loop every ActionUI app runs: **host loads the JSON -> registers handlers for the actionIDs the JSON fires -> reads inputs by id, computes, writes outputs by id.**
- That the *same* `shared/TemperatureConverter.json` drives iOS/macOS (SwiftUI), Android (Compose), and Web (DOM) - only the thin host glue differs.
- The value bridge: read a `TextField` / `Picker` and write a `Text`, all addressed by integer id.
- Picker semantics: a Picker reports its selected option **tag** (here `C` / `F` / `K`), not the visible title.

## Layout

```
TemperatureConverter/
  shared/TemperatureConverter.json     # the one UI skeleton, used by all hosts
  apple/   project.yml + generate_xcodeproj.sh + TemperatureConverterApp.swift  (+ generated .xcodeproj)
  android/ Gradle project (settings/build + app/, wrapper) -> app/.../MainActivity.kt
  web/     index.html + app.js + two symlinks (actionui, TemperatureConverter.json)
  package_web_app.sh                   # emit a self-contained web build into out/
```

ActionUI JSON is strict JSON - **no comments allowed**. The teaching comments live in the host code; the JSON contract is the two tables below.

## Data contract (the JSON's ids)

The root is a plain `VStack` (title `Text` + the card) - no `NavigationStack` or `ScrollView` for an L1 bare-minimum applet. Its `frame` carries `minWidth`/`minHeight` (the macOS window's resize floor) and `idealWidth`/`idealHeight` (the opening size). Only the four interactive elements below carry ids; the containers do not.

| id | element | host does |
|---|---|---|
| 10 | TextField (styled) | **reads** the typed number |
| 20 | Picker "From" | **reads** the selected tag `C`/`F`/`K` (default °C) |
| 30 | Picker "To" | **reads** the selected tag `C`/`F`/`K` (default °F) |
| 40 | Text (result, selectable) | **writes** the converted number; blank when input is blank |

## Action table

| actionID | fired by | host does |
|---|---|---|
| `temp.recompute` | id 10 `valueChangeActionID`; id 20 and id 30 `actionID` | read 10/20/30, convert via Celsius, write 40 |

One action id covers the whole screen: every input fires `temp.recompute`, and the single handler re-reads all three inputs each time. That is the simplest correct pattern - no per-field bookkeeping.

## Run it

### Web (turnkey, no build)

The `web/` folder references the framework and the UI through two symlinks
(`actionui -> ../../../ActionUIWeb`, `TemperatureConverter.json -> ../shared/...`),
so it just works when served from the ActionUI repo root:

```
cd /Users/tkukielk/git/ActionUI
python3 -m http.server 8080 --protocol HTTP/1.1
# then open http://localhost:8080/Examples/TemperatureConverter/web/
```

To get a **self-contained, symlink-free** copy (for zipping/deploying), run
`./package_web_app.sh` - it resolves the symlinks and copies only the core
ActionUIWeb runtime into `out/TemperatureConverter/`, which serves on its own.

### Apple (XcodeGen)

The Xcode project is described by `apple/project.yml` and generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `.xcodeproj` is
committed, so most people just open it and build - no XcodeGen needed. Only after
editing `project.yml` do you regenerate:

```
cd Examples/TemperatureConverter/apple
brew install xcodegen   # one time
./generate_xcodeproj.sh # writes TemperatureConverter.xcodeproj
open TemperatureConverter.xcodeproj
```

The project depends on the ActionUI Swift package at the repo root (products
`ActionUI` + `ActionUISwiftAdapter`) and bundles `shared/TemperatureConverter.json`.
It builds for **both iOS and macOS**: XcodeGen emits two schemes,
`TemperatureConverter_iOS` (deployment target 17.6) and `TemperatureConverter_macOS`
(14.6) - pick one from the scheme selector. The same `TemperatureConverterApp.swift`
host runs on both via the SwiftUI App lifecycle.

### Android (Gradle - no project generator needed)

There is no XcodeGen analog for Android, and none is needed: **a Gradle project
*is* the project**. Android Studio opens the committed Gradle files directly, and
`./gradlew` builds from the command line - nothing to generate. The only special
part is wiring to the framework in the sibling repo dir, done once in
`settings.gradle.kts` as a Gradle **composite build** (`includeBuild` +
dependency substitution maps `com.abracode.actionui:library` to ActionUIAndroid's
`:library`, built from source).

```
# Android Studio: open Examples/TemperatureConverter/android/
# or CLI:
cd Examples/TemperatureConverter/android
./gradlew :temperatureconverter:installDebug    # needs an Android SDK + a device/emulator
```

The shared JSON is single-sourced: `app/build.gradle.kts` adds `../../shared` as an
extra assets directory (`sourceSets["main"].assets.srcDir("../../shared")`), so the
JSON in `shared/` is packaged directly - no copy step. First build also downloads
the Material Symbols font (~15 MB) via the library's own task, so the initial build
needs network.

If Android Studio shows **"Add Configuration"** (no run target) plus a sync error,
that just means the Gradle sync has not succeeded yet - the app run configuration is
created automatically once the first sync passes. (An earlier version used a
build-time `Copy` task whose `Provider` directory AGP 9 rejects with "You cannot add
Provider instances to the Android SourceSet API"; the `srcDir` above is the fix.)

## A cross-platform note (a "walk before run" payoff)

All three hosts update the result `Text` the same way - through the value bridge:
`setElementValue` (Apple), `setString` (Web), `setElementValueFromString` (Android).

That uniformity is recent, and it is the point of these examples. Building this very
applet surfaced that a plain `Text` was *not* value-bearing on Android (only inputs
like `TextField`/`Toggle` were), so the host had to fall back to
`setElementProperty("text")`. Because we own ActionUI, we fixed it in the framework -
Android `Text`, `Label`, `Image`, `Color`, `NavigationLink`, and `ProgressView` are
now value-bearing, matching SwiftUI - and the host code is now identical in shape on
every platform. A cheap converter found and closed a real framework gap before the
big app (SharedCare) ever hit it.

## Build-status notes

The **web** target is fully smoke-tested (served, all assets 200, packaged build
verified symlink-free). The **Apple** (iOS + macOS) and **Android** project files are
written to standard specs; the Apple `.xcodeproj` is committed (regenerate with
`xcodegen generate` only after editing `project.yml`), and the Android Gradle
sync fix (assets `srcDir`) is applied but a full device build was not run here. Expect
at most minor version-pin tweaks on first open. The shared JSON validates against the
ActionUI verifier.
