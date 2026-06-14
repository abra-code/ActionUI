---
id: reference-docs
level: 1
flavors: [claude, capable, lite]
---

## Reference Documents

This skill package includes a `docs/` folder with full per-element documentation:

- `docs/ActionUI-Elements.md` — complete element index (all types, with links)
- `docs/ActionUI-JSON-Guide.md` — JSON structure guide and layout reference
- `docs/ActionUI-MenuBar-JSON-Guide.md` — menu-bar JSON format (`MainMenu.json`): array root, `CommandMenu`/`CommandGroup`/`RemoveMenu`/`RemoveItem`, Button/Divider children
- `docs/Schemas/<Type>.md` — full property specification for a specific element
- `docs/Elements/<Type>.json` — ready-to-use JSON template for a specific element

When a property isn't working as expected, when you need the complete property list for an element, or when your SwiftUI knowledge of a modifier may be incomplete or outdated, read the relevant `docs/Schemas/<Type>.md` file. For a starting-point JSON snippet, use `docs/Elements/<Type>.json`. To customize the application menu bar (a document with an **array** root, distinct from a view), read `docs/ActionUI-MenuBar-JSON-Guide.md`.
