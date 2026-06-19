// Label.js — Label element.
// Web analog of ActionUI/Views/Label.swift (and ActionUIAndroid Views/Label.kt).
//
// A title paired with a leading icon — SwiftUI `Label(title, systemImage:)`,
// collapsing to title-only when there is no image. The icon resolves through the
// shared glyph seam (selectLabelIcon → SymbolIcon.js), the same path as Image and
// Button: `systemImage` (SF Symbol → SF→Material glyph) or `materialName:web`
// (explicit Material glyph, winning when both are present); `imageScale` and the
// `material*` axes tune it. The title is the Label's mutable runtime value
// (valueType String), so get/setElementValue round-trips the text.
//
// Deferred vs. Apple (warn-and-skip, not silent): `imageName` (asset-catalog
// image) needs a name→URL contract web doesn't have yet — the same deferral as
// Image's `assetName` and Button's `assetImage`. A Label carrying only
// `imageName` renders title-only with one warning.

import { register } from "../Common/ActionUIRegistry.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";

register("Label", {
    valueType: "string",

    // Mirrors Label.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("Label title must be a String; ignoring", "warning");
            delete validated.title;
        }
        if (validated.systemImage !== undefined && typeof validated.systemImage !== "string") {
            logger.log("Label systemImage must be a String; ignoring", "warning");
            delete validated.systemImage;
        }
        if (validated.imageName !== undefined && typeof validated.imageName !== "string") {
            logger.log("Label imageName must be a String; ignoring", "warning");
            delete validated.imageName;
        }
        return validated;
    },

    initialValue: (element, properties) => properties.title ?? "",

    buildView: (element, properties, ctx) => {
        const node = document.createElement("span");
        node.className = "aui-label";

        // Leading icon through the shared seam (imageName warns-and-skips). The
        // asset-catalog key is `imageName` on Label, vs `assetImage` on Button.
        const icon = labelIcon(selectLabelIcon(properties, "imageName", "Label", ctx.logger),
            properties, "Label", ctx.logger);
        if (icon) {
            node.classList.add("aui-label-has-icon");
            node.appendChild(icon);
        }

        const titleSpan = document.createElement("span");
        titleSpan.className = "aui-label-title";
        setTitle(titleSpan, properties.title ?? "");
        node.appendChild(titleSpan);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => titleSpan.textContent,
                setValue: (value) => setTitle(titleSpan, String(value ?? "")),
            });
        }
        return node;
    },
});

// The title is the Label's mutable runtime value. An empty title hides the span
// so the icon→title gap reserves no phantom space (SwiftUI's .titleOnly with an
// empty title is just the icon).
function setTitle(span, text) {
    span.textContent = text;
    span.style.display = text === "" ? "none" : "";
}
