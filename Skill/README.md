# ActionUI Skill

A multi-flavor AI agent skill that teaches a model how to author and validate ActionUI JSON.

`Skill/SKILL.md` is the committed `claude` flavor, generated from `master/`. Other flavors live under `dist/` and are gitignored — build them with `Skill/build_skill.py` before installing.

## Layout

```
Skill/
├── master/                       canonical source of truth
│   ├── skill.meta.json           flavor definitions + content manifest
│   └── content/                  modular Markdown content pieces (level 1 = core, level 2 = reference)
│       ├── 01-core.md            JSON node structure + generation rules
│       ├── 02-swiftui-alignment.md   one-paragraph SwiftUI bridge (claude, capable)
│       ├── 03-swiftui-crash-course.md SwiftUI fundamentals (lite only)
│       ├── 04-base-properties.md universal View base properties (level 2)
│       ├── 05-validation.md      validator invocation + error policy
│       ├── 06-element-quick-ref.md one-liner per element (level 2)
│       ├── 07-examples.md        few-shot examples (lite only)
│       ├── 08-patterns.md        real-world layout patterns (level 2)
│       └── 09-reference-docs.md  pointer to docs/ for full element specs
│
├── SKILL.md                      generated; claude flavor; committed
├── dist/                         generated build output; gitignored
│   ├── claude/                   Anthropic Claude Code skill package
│   ├── capable/                  Gemini / Grok / GPT-4o / Llama-3-70B+
│   └── lite/                     Phi-3 / Mistral-7B / local-model class
└── scripts → ../Tools/verifier   symlink to the Python validator
```

The Python verifier in `Tools/verifier/` and the human reference material in `Documentation/` are the same across all flavors; only the SKILL.md prose layer differs.

## Flavors

| Flavor    | Target                                     | Levels | SwiftUI knowledge | Script execution | Tables |
|-----------|--------------------------------------------|--------|-------------------|------------------|--------|
| `claude`  | Anthropic Claude Code (`.claude/skills/`)  | 1 + 2  | assumed           | yes              | yes    |
| `capable` | Gemini, Grok, GPT-4o, Llama-3-70B+         | 1 + 2  | assumed           | no               | yes    |
| `lite`    | Phi-3, Mistral-7B, Llama-3-8B class        | 1 only | crash course      | no               | no     |

## Build

```bash
python3 Skill/build_skill.py                 # all flavors
python3 Skill/build_skill.py --flavor claude # one flavor
python3 Skill/build_skill.py --master-only   # regenerate Skill/SKILL.md only
```

The build also refreshes the committed `Skill/SKILL.md` (claude flavor) so Claude Code picks it up without a build step in consuming repos.

## Install

```bash
# Anthropic Claude Code, current project: drops into ./.claude/skills/actionui/
python3 Skill/install_skill.py claude

# Or into a specific project / user level
python3 Skill/install_skill.py claude --dest /path/to/project
python3 Skill/install_skill.py claude --user

# Capable model: write the SKILL.md to a file to paste/attach
python3 Skill/install_skill.py capable --out ~/Desktop/actionui-capable.md

# Lite (small/local): same; or pipe to stdout
python3 Skill/install_skill.py lite --print | pbcopy
```

The installer auto-runs the build if the requested flavor isn't in `dist/` yet.

### Deployment notes per flavor

- **claude** — installs as a Claude Code skill: `.claude/skills/actionui/{SKILL.md,scripts/,docs/}`. The frontmatter `description` and `name` in SKILL.md govern when the skill activates. The bundled validator and docs are reachable from the agent via the relative paths referenced in SKILL.md.
- **capable** — paste `SKILL.md` into the model's system prompt, or attach as a document for tools that support per-request context. The validator can be invoked manually with `python3 validate_actionui.py <file>` if Python is available; otherwise SKILL.md describes the manual checks.
- **lite** — same as capable, but prefer the trigger keywords in the frontmatter so the model only engages when the user explicitly mentions ActionUI. Tables are stripped from this flavor's SKILL.md to keep the token count low.

## Editing rules

- Edit only files under `master/`. Generated `SKILL.md` and `dist/` will be overwritten on the next build.
- Each content piece has YAML frontmatter declaring its `id`, `level`, and `flavors`. The manifest entry in `skill.meta.json` is authoritative for build-time filtering.
- The Python validator and `Documentation/Schemas/<Type>.md` are the source of truth for element shape. When updating quick-reference tables in `06-element-quick-ref.md`, cross-check property names against `Tools/verifier/schemas/<Type>.json`.
