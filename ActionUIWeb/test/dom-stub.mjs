// dom-stub.mjs — a minimal DOM / window shim for the node:test suite.
//
// ActionUIWeb has no build step and zero runtime dependencies; the tests follow
// suit and add zero third-party dependencies (the only "dependency" is the Node.js
// runtime itself - see test/README.md). This stub covers the slice of the DOM the
// renderer actually touches: element `style`, `classList`, `dataset`, `append` /
// `appendChild`, `addEventListener`, `setAttribute`, and a no-op `querySelector`,
// plus a `document` (createElement + visibilitychange events) and a `window`
// (matchMedia + pagehide events).
//
// It is intentionally NOT a real DOM: there is no layout, no rendering, no CSSOM.
// The tests assert DOM *mutations* (which styles/classes/attributes/listeners a
// function sets), not pixels or computed layout - that is what the renderer's logic
// is, and what a unit test can pin down. For real rendering/animation/layout you need
// a browser (a future, optional Playwright tier). If hand-stubbing ever gets tedious,
// jsdom drops in as a single devDependency with no test changes.

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
        querySelector() { return null; },
        // --- test helpers (not part of the DOM API) ---
        fire(name, ev = {}) { [...(events[name] || [])].forEach((fn) => fn({ target: el, ...ev })); },
        listenerCount(name) { return events[name] ? events[name].size : 0; },
    };
    return el;
}

// Installs `global.document` and `global.window`, returning a controller the test
// uses to drive and inspect them. Call once per test for isolation.
export function installDom() {
    const created = [];
    let visibility = "visible";
    let reducedMotion = false;

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
        createElement(tag) { const el = makeElement(tag); created.push(el); return el; },
    };
    const windowShim = {
        ...winTarget.api,
        matchMedia(query) { return { matches: query.includes("reduced-motion") ? reducedMotion : false }; },
    };

    global.document = documentShim;
    global.window = windowShim;

    return {
        created,
        document: documentShim,
        window: windowShim,
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
