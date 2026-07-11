# ActionUI Examples

Small, self-contained apps that exercise ActionUI end to end on **iOS/macOS, Android, and Web** from one shared JSON UI. Unlike the per-component demos in the test apps, each example here is a *complete little application*: it loads a JSON skeleton, registers action handlers, and supplies real logic in a thin native host.

This folder is a living set, not a fixed syllabus. Only examples worth keeping for teaching value or visual polish are intended to ship; others may appear, change, or be removed without notice. Each example's own README is the source of truth for that app.

## Shipped

| Example | What it proves |
|---|---|
| [Temperature Converter](TemperatureConverter/) | The canonical first loop: load JSON, handle actionIDs, read inputs by id, write outputs by id. Same JSON on all three hosts. |
| [Tip & Bill Splitter](TipBillSplitter/) | Same loop with Slider + Stepper + currency formatting, and a **non-SwiftUI Apple shell** (AppKit on macOS, UIKit on iOS) hosting ActionUI's SwiftUI tree. |

Start with Temperature Converter. Use Tip & Bill Splitter when you care about hosting ActionUI inside a classic AppKit/UIKit app.

## Layout (every example)

```
<App>/
  README.md              # data contract, action table, how to run
  shared/                # the JSON UI (and any shared resources) - identical for all hosts
  apple/                 # host + XcodeGen project.yml (+ committed .xcodeproj)
  android/               # Compose host + Gradle project (composite-builds ActionUIAndroid)
  web/                   # DOM host (no build step); symlinks to shared/ and ActionUIWeb
  package_web_app.sh     # emits a self-contained, symlink-free web build into out/
  .gitignore             # out/, Android build artifacts, Xcode userdata
```

- **Apple:** [XcodeGen](https://github.com/yonaskolb/XcodeGen) `project.yml`; the generated `.xcodeproj` is committed, so open and build without regenerating. Regenerate only after editing `project.yml`.
- **Android:** the committed Gradle files *are* the project - open them in Android Studio or run `./gradlew`. No project generator.
- **Web:** serve from the ActionUI repo root so the `web/` symlinks resolve, or run `./package_web_app.sh` for a deployable copy under `out/`.

The JSON and action IDs are shared; only the host glue differs per platform.

## Conventions

- **Shared JSON, thin hosts.** UI lives once in `shared/`; hosts only load it, handle actionIDs, and move data by id.
- **Action IDs** follow `domain.intent` (e.g. `temp.recompute`).
- **Integer ids** are unique within a JSON file; each example's README documents what every id is for.
- **No precompiled blobs.** Hosts use only source-available platform deps (the ActionUI package itself); prefer none.
- **Comments teach.** Lower-complexity hosts annotate every ActionUI concept; denser hosts stay terser.

## Running a shipped example

Details live in each example's README. In short:

```
# Web (from ActionUI repo root)
python3 -m http.server 8080 --protocol HTTP/1.1
# open http://localhost:8080/Examples/TemperatureConverter/web/

# Apple
open Examples/TemperatureConverter/apple/TemperatureConverter.xcodeproj
# pick the iOS or macOS scheme

# Android
cd Examples/TemperatureConverter/android
./gradlew :temperatureconverter:assembleDebug
```
