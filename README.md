# ActionUI

**Build SwiftUI interfaces from JSON — designed for AI-assisted development and rapid prototyping**

ActionUI is a SwiftUI library that renders dynamic UIs from JSON descriptions. It replaces Interface Builder, Storyboards, or hand-coded SwiftUI with a simple, declarative format that's both human-readable and AI-friendly.

## Quick Example

```json
{
  "type": "Form",
  "properties": {
    "children": [
      {
        "type": "TextField",
        "id": 1,
        "properties": { "title": "Name", "prompt": "Enter your name", "actionID": "nameChanged" }
      },
      {
        "type": "Picker",
        "id": 2,
        "properties": { "title": "Theme", "items": ["Light", "Dark", "Auto"], "actionID": "themeChanged" }
      },
      {
        "type": "Button",
        "id": 3,
        "properties": { "title": "Save", "buttonStyle": "borderedProminent", "actionID": "save" }
      }
    ]
  }
}
```

This produces a fully native SwiftUI form — no Swift code, no Xcode storyboards.

## Key Features

- **50+ SwiftUI components** — layouts, inputs, tables, maps, video, canvas, and more
- **Runtime flexibility** — load UIs from JSON files or network without recompilation
- **Python bridge** — build complete macOS apps in Python with `import actionui`
- **Multi-window, menu bar, dialogs** — native macOS app features out of the box
- **AI-first design** — predictable JSON schema that LLMs generate reliably
- **Cross-platform** — macOS, iOS, iPadOS, watchOS, tvOS, visionOS
- **Multiple language adapters** — Swift, Objective-C, C, C++, Python, JavaScript

## Example Apps using ActionUI

- [TextUtil.app](https://github.com/abra-code/TextUtilApp)
- [Sips.app](https://github.com/abra-code/SipsApp)
- [PillowUI Python applet](https://github.com/abra-code/PillowUI)

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
- [JSON Specifications](Documentation/ActionUI-JSON-Specifications.json)
- [Comparison: ActionUI Python vs tkinter](Documentation/Comparison-vs-tkinter.md)
- [Comparison: ActionUI vs React Native](Documentation/Comparison-vs-ReactNative.md)

## Design Philosophy

**AI-First** — Every API decision considers "can an LLM use this reliably?"

**Fail Gracefully** — Invalid JSON doesn't crash. Properties are validated, missing values get defaults, and the UI degrades gracefully.

**Platform Native** — ActionUI doesn't abstract away SwiftUI — it embraces it. The generated views are real SwiftUI views with full performance and capabilities.

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

## License

ActionUI is licensed under the PolyForm Small Business License 1.0.0 — free for personal projects, open source, education, internal tools, and qualifying small businesses (fewer than 100 people **and** under ~$1.3M adjusted revenue). Larger commercial use requires a paid license — contact me for details.

## Contribution-ware

To encourage adoption, a free license will be granted to companies not meeting the small business criteria but making a **significant** contribution to the project. The contribution classification:
- trivial (bug fix, minor docs),
- non-trivial (new view/modifier, tests, examples),
- significant (major feature, architecture, language adapter, 10+ non-trivial contributions).

## Contributing

By contributing you agree that your contribution may be included in commercial license without compensation or royalties. If you cannot accept these terms, do not contribute.
