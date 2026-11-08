---
id: reference-docs
level: 1
flavors: [claude, capable, lite]
---

## Reference Documents

Full detail lives in the reference docs, not here. In this skill package they are in `docs/`; in an ActionUI checkout, in `Documentation/` (add-on elements: `Add-ons/<Name>/Documentation/Schemas/`). The ActionUI MCP server also serves them as resources `actionui://docs/guide` and `actionui://docs/elements/<Type>`.

- `docs/Schemas/<Type>.md`: every property of one element, its value and events. Read it before using an element you have not used, and whenever a property does not behave as expected.
- `docs/Elements/<Type>.json`: a ready-to-use template for one element.
- `docs/ActionUI-JSON-Guide.md`: structure, layout, platform overrides, charts.
- `docs/ActionUI-Elements.md`: the index of every element.
- `docs/ActionUI-MenuBar-JSON-Guide.md`: the menu-bar document (`MainMenu.json`), whose root is an array, not a view.
