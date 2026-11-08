---
id: validation
level: 1
flavors: [claude, capable, lite]
---

## Validation

After generating or modifying ActionUI JSON, always validate before presenting the result (the path is relative to this skill's folder):

```bash
python3 -B scripts/validate_actionui.py <file-or-directory>
```

Fix every `[ERROR]`. Treat every `[WARNING]` as a probable bug: an unknown property or value is only a warning, and the runtime ignores it, so the document "works" without doing what you wrote. `[INFO]` lines are informational.

Common causes: a misspelled or invented property (check the element's schema), a wrong value type (`"16"` for `16`), a duplicate `id`, a missing required property, a misspelled `type`.

The validator does not catch every mistake that matters: the element notes below list the ones it misses (event keys, `keyboardShortcut` modifiers, empty Picker tags).
