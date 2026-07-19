# Unit Converter (ActionUI Example - the shared-C edition)

Converts a number between units in three categories - **length** (m, cm, km, in, ft, mi), **mass** (kg, g, lb, oz), and **temperature** (C, F, K) - recomputing live as you type or change a unit. One JSON screen drives every platform, exactly as in the other examples.

What makes this one different: **the conversion math is not in the host language. It lives in one C file, `shared/c/convert.c`, and that same file is compiled - unchanged - on Apple (a Clang module imported by Swift) and on Android (the NDK, reached over JNI).** The web host runs a faithful JS port of the same math. The UI is deliberately plain so the focus stays on the C bridging.

## The one idea: one C brain, every platform

```
                       shared/c/convert.c          <- the ONLY conversion logic
                       double aui_convert(category, from, to, value)
                               |
        +----------------------+-----------------------+
        |                      |                       |
   Apple (SPM C target)   Android (NDK + JNI)     Web (JS port)
   apple/ConvertC/        cpp/CMakeLists.txt      web/convert.js
   import ConvertC        NativeBridge.nativeConvert   auiConvert(...)
   aui_convert(...)       -> aui_convert(...)     (mirrors convert.c)
```

- **Apple** packages `convert.c` as a tiny local Swift package, `apple/ConvertC/` (one pure-C library target). SPM auto-generates the Clang module map from `publicHeadersPath: include`, so the module name equals the target name and the Swift host simply writes `import ConvertC` and calls `aui_convert(...)`. No bridging header, no hand-written `module.modulemap`. (This is the pattern from `Private/Example_Host_Patterns.md` section 7, with the Swift side being the app target itself.)
- **Android** compiles the *same* `convert.c` with the NDK via `cpp/CMakeLists.txt` (referenced by relative path - not copied), alongside a thin JNI shim `native-lib.c`. CMake emits `libunitconverter_native.so`; Kotlin's `NativeBridge` object loads it and declares `external fun nativeConvert(...)`, which forwards into `aui_convert`.
- **Web** has no native step, so `web/convert.js` is a line-for-line JS twin of `convert.c` (same factor tables, same affine temperature formulas). Keep the two in lockstep. *(Stretch: compile `convert.c` to WASM with emscripten and call that instead, deleting `convert.js` - see "WASM, the next step" below.)*

Because Apple and Android compile the identical translation unit, they return **bit-for-bit identical numbers**; the JS port matches to full double precision too.

## Single-sourcing the C

`shared/c/convert.c` and `convert.h` are referenced - never duplicated:

- Apple: `apple/ConvertC/Sources/ConvertC/convert.c` and `.../include/convert.h` are **symlinks** back to `shared/c/...`, so SPM compiles the originals.
- Android: `cpp/CMakeLists.txt` lists `${CMAKE_CURRENT_SOURCE_DIR}/../../../../../shared/c/convert.c` directly.
- Web: `web/convert.js` is the hand-kept port (the only intentional copy of the logic).

Edit `shared/c/convert.c` once and both native platforms pick it up on the next build.

## Layout

```
UnitConverter/
  shared/
    UnitConverter.json                 # the one UI skeleton, used by all hosts
    c/convert.c, c/convert.h           # the shared C brain (aui_convert + tables)
  apple/
    project.yml + generate_xcodeproj.sh + UnitConverterApp.swift  (+ generated .xcodeproj)
    ConvertC/                          # local Swift package wrapping convert.c as a Clang module
  android/
    Gradle project (settings/build + wrapper) -> unitconverter/
      src/main/cpp/CMakeLists.txt + native-lib.c   # NDK build of convert.c + JNI shim
      src/main/java/.../MainActivity.kt + NativeBridge
  web/
    index.html + app.js + convert.js + two symlinks (actionui, UnitConverter.json)
  package_web_app.sh                   # emit a self-contained web build into out/
```

ActionUI JSON is strict JSON - **no comments allowed**. The teaching comments live in the host code and in `convert.c`; the JSON contract is the two tables below.

## Data contract (the JSON's ids)

The root is a plain `VStack` (title `Text` + a `GroupBox` card) - no `NavigationStack` or `ScrollView`. Its `frame` carries `minWidth`/`minHeight` (the macOS resize floor) and `idealWidth`/`idealHeight` (the opening size). Only the five interactive elements carry ids.

| id | element | host does |
|---|---|---|
| 5  | Picker "Category" (segmented) | **reads** the tag `length`/`mass`/`temperature`; on change (and once on appear) repopulates 20 + 30 and applies the category's default from/to pair |
| 10 | TextField (amount) | **reads** the typed number |
| 20 | Picker "From" | **reads** the selected unit tag (see tag scheme); **repopulated** per category |
| 30 | Picker "To" | **reads** the selected unit tag; **repopulated** per category |
| 40 | Text (result, selectable) | **writes** the converted number (integers whole, else 2 decimals); blank when input is blank |

**Unit tag scheme.** The from/to pickers list only the current category's units - the host repopulates them on every category change (see the action table). Each tag is `<letter><index>`: the letter is the category (`L` length, `M` mass, `T` temperature) and the index is the unit's position **within that category** - exactly the enum values in `shared/c/convert.h`. So `L0`=meter, `L5`=mile, `M2`=pound, `T1`=Fahrenheit, etc. Mapping a tag to `aui_convert`'s `(category, unit)` arguments is pure string work in every host.

## Action table

| actionID | fired by | host does |
|---|---|---|
| `unit.recompute` | id 10 `valueChangeActionID`; id 20 and id 30 `actionID` | read 10/20/30, call `aui_convert`, write 40 |
| `unit.category`  | id 5 `actionID` **and** id 5 `onAppearActionID` | replace 20 + 30 `options` with the new category's units, select the category's default from/to pair, then recompute |

The from/to pickers can only ever hold units from the current category, because a category change **repopulates** both menus (`setElementProperty` with a new `options` list) and then selects that category's default pair. So a nonsensical cross-category conversion (length -> temperature) is not offer-able in the first place. Runtime `options` is native on Apple/Android (the Picker recomposes off the mutated property); on the web, where there is no reactive re-render, the Picker view registers a small applier that rebuilds the `<select>` options in place. The recompute path still guards on category as a belt-and-braces check (writes `-` if the two tags ever disagree).

**Default conversions per category.** Each category opens on a sensible, non-trivial pair rather than unit -> same unit: length `meter -> foot`, mass `kilogram -> pound`, temperature `Celsius -> Fahrenheit`. The same handler applies the pair on every category switch and once at startup - the category picker declares `onAppearActionID: "unit.category"`, so it fires `unit.category` when it first appears and seeds the initial (length) pair. `onAppearActionID` is a shared cross-platform hook: Apple/Android map it to SwiftUI `.onAppear` / a Compose `DisposableEffect`; on the web the element fires it once after mount (via a microtask). This is the demo's initialization callback - no per-host startup wiring is needed, and the handler always runs with the correct window handle.

## Verified conversions

The same `aui_convert` drives Apple and Android; `convert.js` matches. Spot checks:

| input | result |
|---|---|
| 100 cm -> m | 1 |
| 1 mi -> m | 1609.344 |
| 32 F -> C | 0 |
| 100 C -> F | 212 |
| 1 kg -> lb | 2.204623 |
| 16 oz -> lb | 1 |
| 0 K -> C | -273.15 |

## Run it

### Web (turnkey, no build)

The `web/` folder references the framework and the UI through two symlinks (`actionui -> ../../../ActionUIWeb`, `UnitConverter.json -> ../shared/...`), and `convert.js` is a local file, so it just works when served from the ActionUI repo root:

```
cd ${HOME}/git/ActionUI
python3 -m http.server 8080 --protocol HTTP/1.1
# then open http://localhost:8080/Examples/UnitConverter/web/
```

For a **self-contained, symlink-free** copy (for zipping/deploying), run `./package_web_app.sh` - it resolves the symlinks (and copies `convert.js`) plus the core ActionUIWeb runtime into `out/UnitConverter/`, which serves on its own.

### Apple (XcodeGen + a local C package)

```
cd Examples/UnitConverter/apple
brew install xcodegen   # one time
./generate_xcodeproj.sh # writes UnitConverter.xcodeproj
open UnitConverter.xcodeproj
```

The project depends on the ActionUI Swift package at the repo root (`ActionUI` + `ActionUISwiftAdapter`), on the **local `ConvertC` package** (which compiles `shared/c/convert.c`), and bundles `shared/UnitConverter.json`. It builds for **both iOS and macOS**: XcodeGen emits two schemes, `UnitConverter_iOS` (target 17.6) and `UnitConverter_macOS` (14.6). The C target links into both; the Swift host imports `ConvertC` and calls `aui_convert`.

### Android (Gradle + NDK)

```
# Android Studio: open Examples/UnitConverter/android/
# or CLI:
cd Examples/UnitConverter/android
./gradlew :unitconverter:assembleDebug      # builds the NDK target too
./gradlew :unitconverter:installDebug       # needs an Android SDK + a device/emulator
```

Wiring to the framework is a Gradle **composite build** (`includeBuild` + dependency substitution maps `com.abracode.actionui:library` to ActionUIAndroid's `:library`). The shared JSON is single-sourced via `sourceSets["main"].assets.srcDir("../../shared")`. The native build is configured with `externalNativeBuild { cmake { ... } }` pointing at `cpp/CMakeLists.txt`, which compiles `shared/c/convert.c` + the JNI shim into `libunitconverter_native.so`.

**Requires the NDK and CMake.** Android Studio installs them via *SDK Manager -> SDK Tools -> "NDK (Side by side)"* and *"CMake"*, or from the command line with `sdkmanager "ndk;<version>" "cmake;3.22.1"`. AGP can auto-provision both on first build **only when `cmdline-tools`/`sdkmanager` is present** in the SDK.

## WASM, the next step

`web/convert.js` is a hand-kept port today. The cleaner end state is to compile the very same `shared/c/convert.c` to WebAssembly so the web host runs the identical C as the native ones:

```
emcc shared/c/convert.c -O2 \
  -s EXPORTED_FUNCTIONS='["_aui_convert"]' \
  -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap"]' \
  -s MODULARIZE=1 -o web/convert.wasm.js
```

Then `app.js` would `cwrap("aui_convert", "number", ["number","number","number","number"])` instead of importing `convert.js`. This was not done here because `emcc` was not installed in the authoring environment; with emscripten present it is a drop-in replacement and `convert.js` can be deleted.

## Build-status notes

- **Apple (iOS + macOS): builds clean.** `xcodegen generate` was run and the committed `.xcodeproj` builds for both the macOS destination and the iOS Simulator; the `ConvertC` C target links and the Swift host compiles and calls `aui_convert`.
- **Web: fully smoke-tested.** All assets serve 200 over HTTP (including the symlinked JSON and runtime), `package_web_app.sh` produces a symlink-free copy, and `convert.js` was checked numerically against the C build - identical results.
- **Android: `assembleDebug` builds clean, including the NDK step.** `./gradlew :unitconverter:assembleDebug` succeeded: AGP auto-provisioned the NDK (28.2.x) and CMake (3.22.1), built `shared/c/convert.c` + the JNI shim into `libunitconverter_native.so` for `arm64-v8a` and `x86_64`, and packaged both the `.so` and `assets/UnitConverter.json` into the APK. The `.so` exports `aui_convert`, `nativeConvert`, and `nativeHello`, confirming the shared C compiled. (AGP can auto-download the NDK/CMake only when the SDK has `cmdline-tools`/`sdkmanager`, or after a first install via Android Studio; here AGP fetched them on demand. A device/emulator run, `installDebug`, was not performed.)

The shared JSON validates against the ActionUI verifier, and the *same* `shared/c/convert.c` is what Apple's `ConvertC` package compiles and what the Android NDK build compiles - the whole point of this example. The APK's bundled JSON is byte-identical to `shared/UnitConverter.json`.
