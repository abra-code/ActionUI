# ActionUI

**Build SwiftUI interfaces from JSON — designed for AI-assisted development and low-code rapid prototyping**

ActionUI is a SwiftUI library that enables dynamic view rendering from JSON descriptions. It lowers the barrier to UI development on Apple platforms by replacing Interface Builder, Storyboards or native SwiftUI coding with a simple, declarative JSON format that's both human-readable and AI-friendly.

## Why ActionUI?

Traditional native Apple platform UI development has some hurdles and often a steep learning curve:
- **Interface Builder/Storyboards** are visual tools that don't version well, are hard to automate and are mostly opaque to AI assistants
- **Pure SwiftUI code** requires deep Swift knowledge and platform-specific APIs
- **Rapid prototyping** can be slow in collaborative environment when every UI change requires producing a new build

ActionUI solves these problems by providing:
- **JSON-driven UI** that AI agents can easily generate and modify
- **Declarative syntax** that's simpler than learning SwiftUI directly
- **Runtime flexibility** for dynamic UIs without app recompilation
- **Cross-platform support** across macOS, iOS, iPadOS, watchOS, tvOS, and visionOS

## Perfect for AI-Assisted Development

ActionUI is specifically designed to work seamlessly with AI coding assistants like Claude, Grok, Gemini, GPT, and others:

- **Simple, predictable schema** that LLMs can learn and generate reliably
- **Minimal boilerplate** compared to traditional SwiftUI code
- **Clear validation** with helpful error messages
- **Self-documenting** JSON structure with inline comments

Instead of asking an AI to generate hundreds of lines of SwiftUI code with proper modifiers, bindings, and state management, you can simply request a JSON description and get instant, working UIs.

## Current Implementation Status

ActionUI currently supports **50+ SwiftUI components** including:

**Layout & Containers:**
- Stack layouts: `HStack`, `VStack`, `ZStack`, `LazyHStack`, `LazyVStack`, `LazyHGrid`, `LazyVGrid`, `Grid`
- Navigation: `NavigationStack`, `NavigationSplitView`, `NavigationLink`, `TabView`
- Grouping: `Group`, `Section`, `Form`, `ControlGroup`, `DisclosureGroup`, `GroupBox`, `ScrollView`, `ScrollViewReader`

**Input Controls:**
- Text input: `TextField`, `SecureField`, `TextEditor`
- Selection: `Picker`, `ComboBox`, `DatePicker`, `ColorPicker`, `Toggle`, `Slider`
- Buttons & actions: `Button`, `Link`, `ShareLink`, `Menu`

**Display Elements:**
- Text & images: `Text`, `Label`, `Image`, `AsyncImage`
- Data visualization: `ProgressView`, `Gauge`, `Table`, `List`
- Media: `VideoPlayer`, `Map`, `Canvas`
- Utilities: `Spacer`, `Divider`, `EmptyView`

**Dynamic Loading:**
- `LoadableView` - Dynamically load JSON UI definitions at runtime

**Universal Modifiers:**
All views support common modifiers through the base `View` implementation:
- Layout: `padding`, `frame`, `background`, `cornerRadius`
- Styling: `foregroundColor`, `font`, `opacity`
- Behavior: `hidden`, `disabled`, `actionID`
- And many more through the extensible modifier system

## Quick Example

Here's a simple form with text fields, a picker, and a slider — all defined in JSON:

```json
{
  "type": "Form",
  "id": 100,
  "properties": {
    "children": [
      {
        "type": "Section",
        "properties": {
          "header": "User Information",
          "children": [
            {
              "type": "TextField",
              "id": 101,
              "properties": {
                "placeholder": "Enter your name",
                "actionID": "nameChanged"
              }
            },
            {
              "type": "SecureField",
              "id": 102,
              "properties": {
                "placeholder": "Enter password",
                "actionID": "passwordChanged"
              }
            }
          ]
        }
      },
      {
        "type": "Section",
        "properties": {
          "header": "Preferences",
          "children": [
            {
              "type": "Picker",
              "id": 103,
              "properties": {
                "label": "Theme",
                "items": ["Light", "Dark", "Auto"],
                "actionID": "themeChanged"
              }
            },
            {
              "type": "Toggle",
              "id": 104,
              "properties": {
                "label": "Enable Notifications",
                "actionID": "notificationsToggled"
              }
            },
            {
              "type": "Slider",
              "id": 105,
              "properties": {
                "range": {"min": 0, "max": 100},
                "step": 5,
                "actionID": "volumeChanged"
              }
            }
          ]
        }
      },
      {
        "type": "HStack",
        "properties": {
          "spacing": 20,
          "children": [
            {
              "type": "Button",
              "id": 106,
              "properties": {
                "title": "Cancel",
                "buttonStyle": "bordered",
                "actionID": "cancelPressed"
              }
            },
            {
              "type": "Button",
              "id": 107,
              "properties": {
                "title": "Save",
                "buttonStyle": "borderedProminent",
                "actionID": "savePressed"
              }
            }
          ]
        }
      }
    ]
  }
}
```

This generates a fully functional form that would typically require carefully crafted SwiftUI code, complete with proper spacing, styling, and action handlers.

## Key Features

### Runtime View Construction
Load and render UIs dynamically from JSON files or network sources — no recompilation needed:

```swift
ActionUIModel.shared.loadDescription(from: jsonURL, format: .json, windowUUID: uuid)
```

### Centralized Action Handling
All user interactions route through a simple action handler system:

```swift
ActionUIModel.shared.registerActionHandler(for: "savePressed") { actionID, context in
    // Handle save action
}
```

### State Management
For Views of interest, assign unique integer IDs to maintain their state:

```json
{
  "type": "TextField",
  "id": 42,
  "properties": {
    "placeholder": "Enter text",
    "actionID": "textChanged"
  }
}
```

ActionUI tracks the text field's value internally, provides it via action callbacks and allows the client code set the values and properties of the views.

### Cross-Platform for Apple OSes by Design
Write once, run everywhere. ActionUI automatically handles platform-specific behaviors:
- Conditional support for platform-specific views (e.g., `Table` on macOS)
- Appropriate defaults per platform (e.g., text field styles)
- Graceful fallbacks for unsupported features

**Platform Support:**
- macOS 14.6+
- iOS 17.6+
- iPadOS 17.6+  
- watchOS 10.6+
- tvOS 17.6+
- visionOS 2.6+

### Type-Safe Property Validation
All properties are validated at load time. `ActionUIVerifier` tool allows verifying created or edited json files upfront so no invalid json gets into production.

### Apple HIG Compliance
ActionUI follows Apple Human Interface Guidelines by default, ensuring your dynamically-generated UIs feel native.

## Architecture

ActionUI uses a clean, extensible architecture:

```
┌─────────────────────────────────────────────┐
│           JSON/Plist Description            │
│  { "type": "Button", "id": 1, ... }         │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           ActionUIRegistry                  │
│  - View type registration                   │
│  - Property validation                      │
│  - View construction                        │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│        ActionUIViewConstruction             │
│  - validateProperties()                     │
│  - buildView()                              │
│  - applyModifiers()                         │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│           ActionUIModel                     │
│  - State management (@MainActor)            │
│  - Action routing                           │
│  - View updates                             │
└─────────────────────────────────────────────┘
```

Each SwiftUI view type conforms to `ActionUIViewConstruction`, implementing:
- **Property validation** with sensible defaults
- **View construction** from validated properties  
- **Modifier application** for styling and behavior

## Use Cases

**AI-Generated UIs**  
Let AI assistants like Claude generate entire UIs from natural language descriptions. The JSON format is far easier for LLMs to generate correctly than raw SwiftUI code.

**Rapid Prototyping**  
Iterate on UI designs without recompilation. Update JSON files and see changes instantly during development. Prototype and preview using `ActionUIViewer` tool, which also allows taking screenshots for sharing or providing feedback to an AI agent.

**Dynamic Forms**  
Build apps with server-driven UIs. Download JSON configurations and render completely different interfaces based on user permissions, feature flags, or A/B tests.

**Configuration UIs**  
Generate preference panels, settings screens, or admin interfaces from structured data without hand-coding every field.

**Low-Code Tools**  
Build visual UI builders or form designers that generate ActionUI JSON, enabling non-developers to create Apple platform interfaces.

**Teaching & Learning**  
Lower the barrier for newcomers to Apple development. JSON is easier to learn than SwiftUI's full API surface.

## Design Philosophy

ActionUI is built on several core principles:

**AI-First Design**  
Every API decision considers "can an LLM use this reliably?" The JSON schema is regular, predictable, and well-documented for both humans and AI assistants.

**Fail Gracefully**  
Invalid JSON doesn't crash your app. Properties are validated with errors and warnings, missing values get sensible defaults, and the UI degrades gracefully.

**Platform Native**  
ActionUI doesn't abstract away SwiftUI — it embraces it. The generated views are real SwiftUI views with all the performance and capabilities you expect.

**Language Adapters**  
ActionUI will meet you where you are. Currently available programming environment and language adapters are:
- ActionUISwiftAdapter
- ActionUIObjCAdapter
- ActionUIJavaScriptCoreAdapter
- ActionUIWebKitJSAdapter
- ActionUICppAdapter
- more to come

**Extensible Architecture**  
Adding new view types is straightforward. The protocol-based design makes it easy to extend ActionUI with custom components.

## Current Status

ActionUI is **actively developed** and used for AI-powered UI generation experiments. The core architecture is stable, though some advanced features are still being refined.

**What works well:**
- All 50+ supported view types render correctly
- State management and action routing
- Cross-platform compatibility
- JSON validation and error handling
- AI-assisted UI generation

**In development:**
- Additional view types and modifiers
- Enhanced `Map` support for annotations and overlays
- Comprehensive documentation and examples

## Getting Started

A demo application is included that showcases ActionUI's capabilities:
- **JSON Selector** - Browse all 50+ supported view types
- **Form Example** - See a complete form built entirely from JSON
- **Dynamic Loading** - Load and render JSON at runtime

The demo is intentionally minimal to show the core functionality without unnecessary complexity.

## License

ActionUI is licensed under the PolyForm Small Business License 1.0.0 — free for personal projects, open source, education, internal tools, and qualifying small businesses (fewer than 100 people **and** under ~$1.3M adjusted revenue). Larger commercial use requires a paid license — contact me for details.

## Contribution-ware
To encourage adoption and community contributions a free license will be granted to companies not meeting the small business criteria but contributing significantly to the project.
Contribution classification:
- trivial: small bug fix, minor documentation change or addition, filing a bug
- non-trivial: adding a new view or modifier, important bug fix or minor enhancement, adding several unit tests, adding example or test code, adding important documentation
- significant/major: adding a major feature, solving an architectural problem, implementing advanced build or test infrastructure, adding a new language adapter ready for integration (not just a proof of concept); ten or more non-trivial contributions cross the threshold into the significant contribution

## Contributing
By contributing to the project you agree that your contribution to ActionUI library may be included in commercial license without compensation or royalties to you. If you cannot accept these terms, DO NOT contribute.

## Project Background

ActionUI grew from a long-standing interest in low-code development on Apple platforms. The goal has always been to make UI development more accessible — whether to non-programmers, to developers new to Apple platforms, or to AI assistants that can now help us build software.

With the rise of powerful LLMs, ActionUI's JSON-driven approach has become even more relevant. It turns out that teaching an AI to generate ActionUI JSON is far more reliable than teaching it to write correct SwiftUI code with proper state management, modifiers, and bindings.

