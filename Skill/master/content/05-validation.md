---
id: validation
level: 1
flavors: [claude, capable, lite]
---

## Validation

After generating or modifying ActionUI JSON, always validate before presenting the result:

```bash
python3 Skill/scripts/validate_actionui.py <file-or-directory>
```

Fix all `[ERROR]` issues before presenting. `[WARNING]` lines are likely typos or unsupported properties — investigate and fix if possible. `[INFO]` lines are informational only.

Common errors:
- Unknown property name → typo or hallucinated property; check the element schema
- Wrong value type → e.g., `"spacing": "16"` should be `"spacing": 16`
- Duplicate `id` → change one of the conflicting IDs
- Missing required property → add the required field
- Unknown element `type` → check the spelling; types are PascalCase

Full element documentation is in `docs/Schemas/<Type>.md`. Read the relevant schema when unsure about a property name or value.
