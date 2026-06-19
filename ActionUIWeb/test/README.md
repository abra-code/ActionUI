# ActionUIWeb test suite

Development-only unit tests for the ActionUIWeb renderer. They are **optional** and
never ship: the library and demo load directly in the browser and do not depend on
anything here. Run them while developing; skipping them changes nothing about how
the app runs.

## The one dependency: Node.js

The ActionUIWeb library and demo have **zero runtime dependencies** (vanilla ES
modules, no build step, no bundler). The test suite keeps that spirit: it adds **zero
third-party packages**. Its only dependency is the **Node.js runtime itself**, used
as a dev tool:

- **Node.js >= 20** (declared in `package.json` `engines`). The tests use Node's
  built-in test runner (`node:test`) and assertions (`node:assert`) - both ship with
  Node, nothing to install.
- `package.json` exists *only* for this dev tooling (the `test` script + `engines` +
  `"type": "module"`). The browser ignores it.

This is a deliberate trade: treating "Node.js" as the test dependency (rather than a
test framework like Vitest/Jest, which would pull in a build toolchain) keeps the
project install-free and aligned with its no-build, dependency-averse design.

## Running

```
cd ActionUIWeb
npm test            # -> node --test test/*.test.mjs
# or directly:
node --test test/*.test.mjs
```

The script globs `test/*.test.mjs` so the shared helper (`dom-stub.mjs`) is not run
as a test file.

## How it works (and what it does NOT cover)

The renderer is split between **pure logic** (validation, parsing, color/layout/curve
math) and **DOM-touching code** (modifiers, builders). The pure logic runs in plain
Node with nothing mocked. The DOM-touching code runs against a tiny shared shim,
`dom-stub.mjs` (~90 lines: element `style` / `classList` / `dataset` / `append` /
`addEventListener` / a no-op `querySelector`, plus a `document` and a `window`).

The shim is intentionally **not a real DOM**: there is no layout, no rendering, no
CSSOM. The tests assert DOM *mutations* - which styles / classes / attributes /
listeners a function sets, and what structure it builds - **not pixels or computed
layout**. That is what the renderer's logic *is*, and what a unit test can pin down.

Out of scope here (genuinely needs a real browser - a future, optional Playwright
tier, not run by default):

- visual rendering, actual CSS-transition *animation*, computed layout / sizes;
- anchored positioning that reads `getBoundingClientRect` (`PopoverPlacement`);
- the 2D canvas pass (`CanvasRenderer`), `window.history` navigation
  (`NavigationHistory`), and the native `<dialog>` / top-layer scenes
  (`DialogHost` / `ModalHost` / `ToastHost`).

If hand-stubbing the DOM ever gets tedious as coverage grows, **jsdom** drops in as a
single `devDependency` (a real DOM in Node) with no test rewrites.

## Layout

- `dom-stub.mjs` - shared DOM/window shim + a recording logger. Not a test file.
- `*.test.mjs` - one file per area:
  - `common-core` - PlatformFilter, StackAxis, ActionUIInsertion, Debug
  - `element` - ActionUIElement parsing
  - `modifier-resolver` - resolveColor + applyViewModifiers (build-time CSS)
  - `property-mutation` - applyElementProperty + ActionUIModel.setElementProperty
  - `model-bridge` - value / state / selection bridges
  - `helpers-core` - LoadableSource, MaterialSymbolResolver, SymbolIcon,
    TemplateHelper, MapContract, ShapeStyleHelper
  - `searchable`, `lifecycle`, `animation` - the corresponding modifiers/hooks
  - `views-validate` - every registered view's `validateProperties`
  - `menubar`, `toolbar` - the menu-bar parser and toolbar bucketing
  - `actionui-api` - the public Window / Application API + a present() smoke test
