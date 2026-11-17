# ActionUI

**Build native interfaces from JSON, across Apple, Android, Linux, and the Web — designed for AI-assisted development and rapid prototyping**

ActionUI renders dynamic UIs from JSON descriptions. One JSON document drives **four native renderers** from a shared schema: SwiftUI on Apple platforms, GTK 4 and libadwaita on Linux, Jetpack Compose on Android, and DOM/CSS in the browser. It replaces Interface Builder, Storyboards, or hand-coded UI with a simple, declarative format that's both human-readable and AI-friendly.

**[Try the live browser demo →](https://abracode.com/ActionUIWeb/demo/)** (no install, no local server)

## Quick Example

```json
{
  "type": "Form",
  "children": [
    {
      "type": "TextField",
      "id": 1,
      "properties": { "title": "Name", "prompt": "Enter your name", "actionID": "nameChanged" }
    },
    {
      "type": "Picker",
      "id": 2,
      "properties": { "title": "Theme", "options": ["Light", "Dark", "Auto"], "actionID": "themeChanged" }
    },
    {
      "type": "Button",
      "id": 3,
      "properties": { "title": "Save", "buttonStyle": "borderedProminent", "actionID": "save" }
    }
  ]
}
```

This produces a fully native form — a SwiftUI form on Apple, a GTK form on Linux, a Compose form on Android, a DOM form on the Web — from the same JSON, with no per-platform UI code and no storyboards.

## Key Features

- **Four native renderers, one JSON** — SwiftUI (Apple), GTK 4 and libadwaita (Linux), Jetpack Compose (Android), DOM/CSS (Web), at feature parity across 60+ element types — layouts, inputs, tables, maps, video, canvas, and more
- **Runtime flexibility** — load UIs from JSON files or network without recompilation
- **Add-on architecture** — third-party element types (Chat, Diff, RichText, QuickLook, CachedImage, HostSurface) plug into the engine without living in core
- **Python bridge** — build complete macOS and Linux apps in Python with `import actionui`
- **Rust bridge** - native macOS and Linux interface in JSON, program logic in Rust, one self-contained executable (see [ActionUIRust](ActionUIRust/README.md))
- **Multi-window, menu bar, dialogs** — native app features out of the box
- **AI-first design** — predictable JSON schema that LLMs generate reliably - for agent skill information see [Skill/README.md](Skill/README.md)
- **Apple platforms** — macOS, iOS, iPadOS, watchOS, tvOS, visionOS
- **Multiple language adapters** — Swift, Objective-C, C, C++, Python, JavaScript, Rust
- **Linux** - native GNOME interfaces (GTK 4 and libadwaita) from the same JSON and the same C interface: every core element type, and the RichText, CachedImage, Diff and HostSurface add-ons; Python, Node.js and Rust programs too (see [ActionUIAdwaita](ActionUIAdwaita/README.md) for what differs)

## Example Apps using ActionUI

- [AppletBuilder.app](https://github.com/abra-code/OMC/tree/master/Distribution)
- [TextUtil.app](https://github.com/abra-code/TextUtilApp)
- [Sips.app](https://github.com/abra-code/SipsApp)
- [AIChat.app](https://github.com/abra-code/AIChatApp)
- [ICEdit.app](https://github.com/abra-code/ICEditApp)
- [PillowUI Python applet](https://github.com/abra-code/PillowUI)
- [NPMExplorer Node.js applet](https://github.com/abra-code/NPMExplorer)


## Python Example

```python
import actionui

app = actionui.Application(name="MyApp")
window = actionui.Window.from_file("ui.json", title="My App")
app.load_and_present_window(window)

@app.action("save")
def on_save(ctx):
    name = window.get_string(view_id=1)
    print(f"Saving: {name}")

app.run()
```

## Documentation

- [Architecture & Technical Details](Documentation/Architecture.md)
- [ActionUI on Linux](ActionUIAdwaita/README.md)
- [JSON Guide](Documentation/ActionUI-JSON-Guide.md)
- [Element Reference](Documentation/ActionUI-Elements.md)
- [Comparison: ActionUI Python vs tkinter](Documentation/Comparison-vs-tkinter.md)
- [Comparison: ActionUI vs React Native](Documentation/Comparison-vs-ReactNative.md)

## Design Philosophy

**AI-First** — Every API decision considers "can an LLM use this reliably?"

**Fail Gracefully** — Invalid JSON doesn't crash. A property of the wrong type is ignored, missing values get defaults, and the UI degrades gracefully.

**Platform Native** — ActionUI doesn't abstract platforms away — it embraces each one. The generated views are real SwiftUI views on Apple, real GTK widgets on Linux, real Compose composables on Android, and real DOM on the Web, with each platform's full performance and capabilities.

**Minimal Complexity** — JSON defines the UI, your code handles the logic. No state management framework, no build toolchain, no widget hierarchy to manage.

## Platform Support

| Platform | Minimum Version |
|----------|----------------|
| macOS    | 14.6+          |
| iOS      | 17.6+          |
| iPadOS   | 17.6+          |
| watchOS  | 10.6+          |
| tvOS     | 17.6+          |
| visionOS | 2.6+           |
| Android  | 12.0+          |
| Web      | Any modern browser (ES modules, no build step) |
| Linux    | GNOME 48+ (GTK 4.18, libadwaita 1.7), e.g. Debian 13, Ubuntu 26.04 |

## License

ActionUI is licensed under the PolyForm Small Business License 1.0.0 — free for personal projects, open source, education, internal tools, and qualifying small businesses (fewer than 100 people **and** under ~$1.3M adjusted revenue). Larger commercial use requires a paid license — contact me for details.

## Contribution-ware

To encourage adoption, a free license will be granted to companies not meeting the small business criteria but making a **significant** contribution to the project. The contribution classification:
- trivial (bug fix, minor docs),
- non-trivial (new view/modifier, tests, examples),
- significant (major feature, architecture, language adapter, 10+ non-trivial contributions).

## Contributing

By contributing you agree that your contribution may be included in commercial license without compensation or royalties. If you cannot accept these terms, do not contribute.
