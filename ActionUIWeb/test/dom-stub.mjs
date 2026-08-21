// dom-stub.mjs — a minimal DOM / window shim for the node:test suite.
//
// ActionUIWeb has no build step and zero runtime dependencies; the tests follow
// suit and add zero third-party dependencies (the only "dependency" is the Node.js
// runtime itself - see test/README.md). This stub covers the slice of the DOM the
// renderer actually touches: element `style`, `classList`, `dataset`, `append` /
// `appendChild` / `insertBefore`, `addEventListener`, `set/get/removeAttribute`, `focus` /
// `blur` (tracked via `document.activeElement`), and a no-op `querySelector`,
// plus a `document` (createElement + visibilitychange events), a `window`
// (matchMedia + pagehide events), and a `ResizeObserver` that never auto-fires (a
// test drives it via the controller's `fireResize`).
//
// matchMedia is controllable, mirroring `fireResize`: it resolves a
// `prefers-reduced-motion` query against `setReducedMotion(on)` and a
// `min-width` / `max-width` query against `setViewportWidth(px)` (default a wide
// 1024, so compact-width branches are off unless a test opts in). This lets the
// pure modality predicates (Helpers/Modality.js) be exercised headlessly.
//
// It is intentionally NOT a real DOM: there is no layout, no rendering, no CSSOM.
// The tests assert DOM *mutations* (which styles/classes/attributes/listeners a
// function sets), not pixels or computed layout - that is what the renderer's logic
// is, and what a unit test can pin down. For real rendering/animation/layout you need
// a browser (a future, optional Playwright tier). If hand-stubbing ever gets tedious,
// jsdom drops in as a single devDependency with no test changes.

// The currently-focused stub element (the analog of document.activeElement), set by
// el.focus() and exposed via documentShim.activeElement. Reset per installDom.
let focusedElement = null;

// Removes a node from whatever parent currently holds it, so an insert can re-add it.
// The node's STRUCTURE, stored as properties here but never an attribute in a real
// DOM - see getAttribute below. Deliberately NOT `value` / `checked`: those really are
// attributes, and `<progress>` expresses indeterminate by REMOVING `value`
// (`Views/ProgressView.js`), so guarding them would make removeAttribute a silent
// no-op for the one element that most needs it - a test asserting indeterminate would
// then pass in every state.
const NODE_OWN_KEYS = new Set([
    "style", "children", "classList", "className", "parentNode", "dataset",
    "textContent", "tagName", "__events",
]);

function detachNode(node) {
    const parent = node.parentNode;
    if (!parent) return;
    parent.children = parent.children.filter((n) => n !== node);
    node.parentNode = null;
}

// A fake element exposing the surface the renderer uses.
export function makeElement(tag = "div") {
    const classes = new Set();
    const events = {};
    const el = {
        tagName: String(tag).toUpperCase(),
        type: "",
        placeholder: "",
        value: "",
        title: "",
        textContent: "",
        className: "",
        disabled: false,
        // style is a plain bag of inline props; setProperty/getPropertyValue cover the
        // CSSOM custom-property path the renderer uses (e.g. --aui-swipe-color, --aui-gauge-fill).
        style: {
            setProperty(name, val) { this[name] = val; },
            getPropertyValue(name) { return this[name] ?? ""; },
        },
        dataset: {},
        children: [],
        classList: {
            add: (c) => classes.add(c),
            remove: (c) => classes.delete(c),
            toggle: (c, force) => {
                const on = force === undefined ? !classes.has(c) : !!force;
                if (on) classes.add(c); else classes.delete(c);
                return on;
            },
            contains: (c) => classes.has(c),
        },
        parentNode: null,
        // Nearest ancestor-OR-SELF matching `selector`, which is the part of `closest` the
        // renderer depends on: ModifierResolver asks ".aui-disabled" ("is this node, or
        // anything above it, disabled?") and List.js asks a comma-separated tag list
        // ("button, input, select, textarea, a") to tell a click on a control from a click
        // on inert row content. Starting at the node ITSELF, not its parent, is what makes
        // the first question answer true for a container carrying its own `disabled`.
        // Unsupported selector shapes return null rather than throwing, matching the
        // permissive spirit of the rest of this stub.
        closest(selector) {
            if (typeof selector !== "string") return null;
            const parts = selector.split(",").map((s) => s.trim()).filter(Boolean);
            const matches = (n) => parts.some((part) => (part.startsWith(".")
                ? !!n.classList?.contains(part.slice(1))
                : n.tagName === part.toUpperCase()));
            for (let n = el; n; n = n.parentNode) {
                if (matches(n)) return n;
            }
            return null;
        },
        // Attributes are plain properties on the node, which is enough for the
        // renderer (it only ever sets and clears them) and lets a test read one back
        // as either `node.id` or `node.getAttribute("id")`.
        setAttribute(key, val) { el[key] = val; },
        // ATTRIBUTES only. The stub keeps them as plain properties, so a naive lookup
        // would also answer for the node's own machinery - `getAttribute("style")`
        // returning the style OBJECT, `getAttribute("children")` an array - which is
        // not what any caller means and would quietly pass a wrong assertion.
        getAttribute(key) {
            if (NODE_OWN_KEYS.has(key)) return null;
            const v = el[key];
            return v === undefined || typeof v === "function" ? null : v;
        },
        // Needed by any element that clears an attribute to express a state - a
        // ProgressView drops `value` to become indeterminate - so without it the
        // stub threw on rendering one at all.
        removeAttribute(key) { if (!NODE_OWN_KEYS.has(key)) delete el[key]; },
        // Inserting a node that already has a parent MOVES it: the real DOM detaches it
        // from the old parent first, and code that reparents a node (NavigationStack moves
        // one persistent-toolbar node between panes) relies on that to keep exactly one
        // live node per element id. Without the detach the stub reported the node in every
        // pane it had ever been in, so a one-instance assertion failed no matter what the
        // renderer did - it could not tell a correct move from a per-pane copy.
        append(...nodes) { nodes.forEach((n) => { if (n) { detachNode(n); n.parentNode = el; el.children.push(n); } }); },
        appendChild(node) { if (node) { detachNode(node); node.parentNode = el; el.children.push(node); } return node; },
        insertBefore(node, ref) {
            if (!node) return node;
            if (node === ref) return node; // the real DOM makes this a no-op
            detachNode(node);
            node.parentNode = el;
            const i = ref ? el.children.indexOf(ref) : -1;
            if (i < 0) el.children.push(node); else el.children.splice(i, 0, node);
            return node;
        },
        replaceChildren(...nodes) {
            el.children.forEach((n) => { if (n && n.parentNode === el) n.parentNode = null; });
            nodes.forEach((n) => { if (n) detachNode(n); });
            nodes.forEach((n) => { if (n) n.parentNode = el; });
            el.children = nodes;
        },
        remove() {
            const parent = el.parentNode;
            if (parent) { parent.children = parent.children.filter((n) => n !== el); el.parentNode = null; }
        },
        addEventListener(name, fn) { (events[name] ||= new Set()).add(fn); },
        removeEventListener(name, fn) { events[name]?.delete(fn); },
        focus() { focusedElement = el; },          // tracked via document.activeElement
        blur() { if (focusedElement === el) focusedElement = null; },
        querySelector() { return null; },
        // Minimal descendant query: a single class (".foo") or tag selector. Enough
        // for List's children-mode applySelectionStyles (querySelectorAll(".aui-list-row")).
        querySelectorAll(selector) {
            const matches = (n) => typeof selector === "string" && (selector.startsWith(".")
                ? (typeof n.className === "string" && n.className.split(/\s+/).includes(selector.slice(1)))
                : n.tagName === selector.toUpperCase());
            const out = [];
            const walk = (n) => { for (const c of n.children) { if (matches(c)) out.push(c); walk(c); } };
            walk(el);
            return out;
        },
        // The element's own listener sets, reachable from a descendant so `fire` can
        // walk up and bubble. Not a DOM property - the real DOM keeps this private.
        __events: events,
        // --- test helpers (not part of the DOM API) ---
        // `fire` dispatches on this element and then walks UP the parent chain, the way
        // a real DOM event bubbles. Bubbling is what makes a nested-handler test honest:
        // a Button inside a container that also carries an actionID triggers BOTH
        // listeners in a browser, so a stub that only ever fired locally could neither
        // see that double dispatch nor prove a guard against it. `stopPropagation()`
        // ends the walk, as in the DOM. Pass `{ bubbles: false }` for the events that
        // genuinely do not bubble (focus, blur).
        //
        // stopPropagation() ends the walk at the end of the CURRENT node's listeners, as
        // in the DOM: the remaining listeners on that node still run, only ancestors are
        // skipped. (Skipping the rest of the current node's listeners too would be
        // stopImmediatePropagation, which nothing here needs.)
        //
        // preventDefault is a no-op that records itself. It exists because bubbling made
        // ancestor handlers reachable from a descendant `fire` for the first time, and
        // several of them call it (Views/List.js, Views/NavigationStack.js,
        // Helpers/ContextMenuModifier.js). Without it those handlers would throw on an
        // event this stub synthesized rather than on anything the renderer did wrong.
        fire(name, ev = {}) {
            const { bubbles = true, ...rest } = ev;
            let propagating = true;
            // preventDefault goes BEFORE the spread so a caller-supplied spy still wins -
            // several tests pass one and assert it was called. stopPropagation goes AFTER,
            // because the walk below depends on it and a caller must not be able to
            // substitute one that does not stop anything.
            const event = {
                target: el,
                defaultPrevented: false,
                preventDefault() { event.defaultPrevented = true; },
                ...rest,
                stopPropagation() { propagating = false; },
            };
            for (let n = el; n; n = n.parentNode) {
                const handlers = n.__events?.[name];
                if (handlers) {
                    event.currentTarget = n;
                    [...handlers].forEach((fn) => fn(event));
                }
                if (!bubbles || !propagating) break;
            }
            return event;
        },
        listenerCount(name) { return events[name] ? events[name].size : 0; },
    };
    return el;
}

// A minimal ResizeObserver stub: it records observed targets and the callback but
// never fires on its own (real layout is a browser concern), so code guarded by
// `typeof ResizeObserver !== "undefined"` builds without auto-resizing - e.g. the
// Table never auto-fills, NavigationSplitView/TabView stay expanded - until a test
// explicitly drives it via the controller's `fireResize`.
class ResizeObserverStub {
    constructor(callback) {
        this.callback = callback;
        this.targets = [];
        ResizeObserverStub.instances.push(this);
    }
    observe(target) { this.targets.push(target); }
    unobserve(target) { this.targets = this.targets.filter((t) => t !== target); }
    disconnect() { this.targets = []; }
}
ResizeObserverStub.instances = [];

// Installs `global.document` and `global.window`, returning a controller the test
// uses to drive and inspect them. Call once per test for isolation.
export function installDom() {
    const created = [];
    let visibility = "visible";
    let reducedMotion = false;
    let viewportWidth = 1024; // a wide (desktop) default: compact-width queries are false unless a test opts in
    ResizeObserverStub.instances = []; // reset for isolation
    focusedElement = null;             // reset focus tracking

    const makeTarget = () => {
        const events = {};
        return {
            api: {
                addEventListener(name, fn) { (events[name] ||= new Set()).add(fn); },
                removeEventListener(name, fn) { events[name]?.delete(fn); },
            },
            fire(name, ev = {}) { [...(events[name] || [])].forEach((fn) => fn(ev)); },
            count(name) { return events[name] ? events[name].size : 0; },
        };
    };
    const docTarget = makeTarget();
    const winTarget = makeTarget();

    const documentShim = {
        ...docTarget.api,
        get visibilityState() { return visibility; },
        get activeElement() { return focusedElement; },
        createElement(tag) { const el = makeElement(tag); created.push(el); return el; },
    };
    const windowShim = {
        ...winTarget.api,
        matchMedia(query) { return { matches: evaluateMedia(query) }; },
    };

    // Resolve the slice of media queries the renderer asks about: reduced-motion
    // against the flag, and min/max-width against the current viewport width.
    // Anything else is treated as not matching.
    function evaluateMedia(query) {
        if (query.includes("reduced-motion")) return reducedMotion;
        const max = query.match(/max-width:\s*(\d+)/);
        if (max) return viewportWidth <= Number(max[1]);
        const min = query.match(/min-width:\s*(\d+)/);
        if (min) return viewportWidth >= Number(min[1]);
        return false;
    }

    global.document = documentShim;
    global.window = windowShim;
    global.ResizeObserver = ResizeObserverStub;

    return {
        created,
        document: documentShim,
        window: windowShim,
        // Fire any ResizeObserver observing `target` with a content-box `width`,
        // driving the width-class collapse code (NavigationSplitView / TabView).
        fireResize: (target, width) => {
            for (const obs of ResizeObserverStub.instances) {
                if (obs.targets.includes(target)) obs.callback([{ target, contentRect: { width } }], obs);
            }
        },
        findCreated: (pred) => created.find(pred),
        fireDocument: (name, ev) => docTarget.fire(name, ev),
        fireWindow: (name, ev) => winTarget.fire(name, ev),
        documentListenerCount: (name) => docTarget.count(name),
        windowListenerCount: (name) => winTarget.count(name),
        setVisibility: (state) => { visibility = state; },
        setReducedMotion: (on) => { reducedMotion = on; },
        setViewportWidth: (px) => { viewportWidth = px; },
    };
}

// A recording logger matching the renderer's `{ log(message, level) }` shape, with
// helpers to assert messages by level/substring.
export function makeLogger() {
    const messages = [];
    return {
        messages,
        log(message, level = "info") { messages.push({ message, level }); },
        warned(substr) { return messages.some((m) => m.level === "warning" && m.message.includes(substr)); },
        warningCount() { return messages.filter((m) => m.level === "warning").length; },
    };
}
