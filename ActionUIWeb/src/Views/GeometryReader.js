// GeometryReader.js — GeometryReader element.
// Web analog of ActionUI/Views/GeometryReader.swift (and ActionUIAndroid
// Views/GeometryReader.kt).
//
// ActionUI's GeometryReader is NOT SwiftUI's closure-based proxy (a JSON child
// cannot run a closure). It is the cross-platform reinterpretation the schema
// defines (Documentation/Schemas/GeometryReader.md): a greedy container holding a
// single `content` child, aligned within the box (default topLeading), that
// reports its measured size to the host as observable state — `states["size"] =
// [width, height]`, read on demand via getElementState(id, "size"). No value
// bridge, no resize action; the host reads the size when it wants to make a
// responsive decision, with the same call on Apple, Android, and the web.
//
// Web specifics:
//   * Greedy fill is the .aui-shape idiom (flex-grow:1 + align-self:stretch);
//     an explicit numeric frame dimension pins the box (flex-grow:0 inline), the
//     same discipline createShapeBox uses. CSS lays it out — no JS measure loop.
//   * The single-cell grid places the content child by `alignment` via place-self
//     (the ZStack alignment vocabulary), defaulting to topLeading like Apple.
//   * A ResizeObserver (the Canvas pattern) keeps a live border-box size that the
//     state binding returns; size is reported in CSS px (the host's coordinate
//     space), seeded [0, 0] until the first layout.
//   * Bounded-axis caveat (same as Android's): on an unbounded axis — inside a
//     vertical scroller, where height is intrinsic — "fill available space" has
//     nothing to fill and the box collapses; give it an explicit frame extent
//     there. See Private/Web_Porting_Notes.md (GeometryReader).

import { register } from "../Common/ActionUIRegistry.js";

// SwiftUI alignments -> CSS place-self (block/vertical + inline/horizontal),
// the same mapping ZStack uses. GeometryReader's default is topLeading (NOT
// center like most containers).
const GR_ALIGN = {
    topLeading: "start start", top: "start center", topTrailing: "start end",
    leading: "center start", center: "center center", trailing: "center end",
    bottomLeading: "end start", bottom: "end center", bottomTrailing: "end end",
};
const GR_VALID = Object.keys(GR_ALIGN);

register("GeometryReader", {
    valueType: "none",

    // Mirrors GeometryReader.swift validateProperties: an invalid alignment warns
    // and defaults to topLeading (warning text matched).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.alignment !== undefined) {
            if (typeof validated.alignment !== "string" || !GR_VALID.includes(validated.alignment)) {
                logger.log(`GeometryReader alignment '${validated.alignment}' invalid; defaulting to 'topLeading'`, "warning");
                validated.alignment = "topLeading";
            }
        }
        return validated;
    },

    // The documented size store (states["size"] = [width, height]); [0, 0] until
    // the first layout reports a real size.
    initialStates: () => ({ size: [0, 0] }),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-geometry-reader";

        // An explicit numeric frame dimension pins the greedy box (same as
        // createShapeBox), so a frame'd reader keeps its size in a flex stack.
        const frame = properties.frame;
        if (typeof frame === "object" && frame !== null
            && (typeof frame.width === "number" || typeof frame.height === "number")) {
            node.style.flexGrow = "0";
        }

        const content = element.subviews?.content;
        if (content) {
            const child = ctx.build(content);
            child.style.placeSelf = GR_ALIGN[properties.alignment] ?? GR_ALIGN.topLeading;
            node.appendChild(child);
        }

        // Live measured size (border box, CSS px), returned by the state binding.
        let size = [0, 0];
        const observer = new ResizeObserver((entries) => {
            const box = entries[0]?.borderBoxSize?.[0];
            size = box
                ? [box.inlineSize, box.blockSize]
                : [node.clientWidth, node.clientHeight];
        });
        observer.observe(node);

        // states["size"] is read-only from the host (a measured quantity); a
        // setState is a no-op so setElementState never throws.
        if (element.id > 0) {
            ctx.model.bindState(element.id, {
                getState: (key) => (key === "size" ? [...size] : undefined),
                setState: () => {},
            });
        }

        node._auiDestroy = () => observer.disconnect();
        return node;
    },
});
