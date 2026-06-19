// dom-stub.mjs — a minimal DOM / window shim for the node:test suite.
//
// ActionUIWeb has no build step and zero runtime dependencies; the tests follow
// suit and add zero third-party dependencies (the only "dependency" is the Node.js
// runtime itself - see test/README.md). This stub covers the slice of the DOM the
// renderer actually touches: element `style`, `classList`, `dataset`, `append` /
// `appendChild` / `insertBefore`, `addEventListener`, `setAttribute`, `focus` /
// `blur` (tracked via `document.activeElement`), and a no-op `querySelector`,
// plus a `document` (createElement + visibilitychange events), a `window`
// (matchMedia + pagehide events), and a `ResizeObserver` that never auto-fires (a
// test drives it via the controller's `fireResize`).
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
        style: {},
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
        setAttribute(key, val) { el[key] = val; },
        append(...nodes) { nodes.forEach((n) => { if (n) n.parentNode = el; }); el.children.push(...nodes); },
        appendChild(node) { if (node) node.parentNode = el; el.children.push(node); return node; },
        insertBefore(node, ref) {
            if (!node) return node;
            node.parentNode = el;
            const i = ref ? el.children.indexOf(ref) : -1;
            if (i < 0) el.children.push(node); else el.children.splice(i, 0, node);
            return node;
        },
        replaceChildren(...nodes) {
            el.children.forEach((n) => { if (n && n.parentNode === el) n.parentNode = null; });
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
        // --- test helpers (not part of the DOM API) ---
        fire(name, ev = {}) { [...(events[name] || [])].forEach((fn) => fn({ target: el, ...ev })); },
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
        matchMedia(query) { return { matches: query.includes("reduced-motion") ? reducedMotion : false }; },
    };

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
