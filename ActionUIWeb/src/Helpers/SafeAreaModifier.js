// SafeAreaModifier.js - the `ignoresSafeArea` / `safeAreaInset` modifiers.
// Web analog of ActionUI/Views/View.swift (.ignoresSafeArea / .safeAreaInset) and the Android
// SafeAreaHelper.kt. The web safe area is the CSS `env(safe-area-inset-*)` (the notch / home
// indicator); env() is 0 on a non-notched / desktop screen, so both are no-ops there.
//
// - ignoresSafeArea: pulls the element out by the safe-area inset on the chosen edges (negative
//   env() margins), so e.g. a background bleeds under the notch. A property on any view.
// - safeAreaInset: a WRAPPING modifier - the inset view is pinned to an edge with that edge's
//   env() padding (so it clears the notch / home indicator) and the main content takes the rest.

const EDGE_TO_CSS = { top: "top", bottom: "bottom", leading: "left", trailing: "right" };

// Which physical edges a safe-area `edges` token covers.
function edgesFor(token) {
    switch (token) {
        case "top": return ["top"];
        case "bottom": return ["bottom"];
        case "leading": return ["left"];
        case "trailing": return ["right"];
        case "horizontal": return ["left", "right"];
        case "vertical": return ["top", "bottom"];
        default: return ["top", "bottom", "left", "right"]; // all
    }
}

// ignoresSafeArea (any view): negative env() margins on the chosen edges so the element extends
// into the safe area. `true` = all edges; an object narrows via `edges`. Called from
// ModifierResolver.applyViewModifiers; a no-op when the property is absent/false.
export function applyIgnoresSafeArea(node, properties) {
    const value = properties.ignoresSafeArea;
    if (value === undefined || value === false) return;
    const token = (value === true) ? "all"
        : (value && typeof value === "object" && typeof value.edges === "string" ? value.edges : "all");
    for (const edge of edgesFor(token)) {
        node.style[`margin-${edge}`] = `calc(-1 * env(safe-area-inset-${edge}))`;
    }
}

// safeAreaInset: wraps `node` so the inset subview sits at an edge (with that edge's safe-area
// padding) and the content fills the rest. A WRAPPING modifier (returns a wrapper, keeps
// data-aui-id on the inner node), called from ActionUIRegistry.buildElement. A no-op when absent.
export function wrapWithSafeAreaInset(node, element, properties, ctx) {
    const inset = element.subviews?.safeAreaInset;
    if (!inset) return node;

    const edge = (typeof inset.properties?.safeAreaEdge === "string") ? inset.properties.safeAreaEdge : "bottom";
    const cssEdge = EDGE_TO_CSS[edge] ?? "bottom";
    const vertical = cssEdge === "top" || cssEdge === "bottom";

    const wrapper = document.createElement("div");
    wrapper.className = "aui-safe-area-inset";
    wrapper.style.flexDirection = vertical ? "column" : "row";

    const bar = document.createElement("div");
    bar.className = "aui-safe-area-bar";
    bar.style[`padding-${cssEdge}`] = `env(safe-area-inset-${cssEdge})`;
    bar.appendChild(ctx.build(inset));

    const content = document.createElement("div");
    content.className = "aui-safe-area-content";
    content.appendChild(node);

    // Bar pinned to its edge: top/leading -> before the content, bottom/trailing -> after.
    if (cssEdge === "top" || cssEdge === "left") wrapper.append(bar, content);
    else wrapper.append(content, bar);
    return wrapper;
}
