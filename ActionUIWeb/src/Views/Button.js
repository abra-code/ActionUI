// Button.js — Button element.
// Web analog of ActionUI/Views/Button.swift (PoC subset).
//
// Properties: title (String, defaults to ""), role ("destructive" | "cancel"),
// systemImage/assetImage/imageScale. A leading icon resolves through the shared
// glyph seam (selectLabelIcon → SymbolIcon.js), the same path as Image: an SF
// Symbol (`systemImage`) or an explicit Material glyph (`materialName:web`, which
// wins when both are present). With a title the button is icon + title; with an
// empty title it is icon-only. `assetImage` (asset-catalog) is deferred and
// warns-and-skips, mirroring Image's `assetName` and the Android Button.
// Action context carries the button title, matching the Swift implementation.
// `buttonStyle` is a View-level modifier on Apple (applied via applyViewModifiers);
// on web it is styled here pending a ModifierResolver home, so it is not part of
// this element's schema validation.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";

const BUTTON_STYLES = new Set([
    "automatic", "bordered", "borderedProminent", "borderless", "plain",
]);

register("Button", {
    valueType: "none",

    // Mirrors Button.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("Invalid type for Button title: expected String, ignoring", "warning");
            delete validated.title;
        }
        if (validated.systemImage !== undefined && typeof validated.systemImage !== "string") {
            logger.log("Invalid systemImage type", "warning");
            delete validated.systemImage;
        }
        if (validated.assetImage !== undefined && typeof validated.assetImage !== "string") {
            logger.log("Invalid assetImage type (expected String)", "warning");
            delete validated.assetImage;
        }
        if (validated.imageScale !== undefined && typeof validated.imageScale !== "string") {
            logger.log("Invalid imageScale type", "warning");
            delete validated.imageScale;
        }
        if (typeof validated.role === "string") {
            if (!["destructive", "cancel"].includes(validated.role)) {
                logger.log(`Invalid Button role '${validated.role}', ignoring`, "warning");
                delete validated.role;
            }
        } else if (validated.role !== undefined) {
            logger.log("Invalid type for Button role: expected String, ignoring", "warning");
            delete validated.role;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("button");
        // buttonStyle: View-level styling (see header); unknown values fall back
        // to "bordered" silently rather than as a schema warning.
        const style = BUTTON_STYLES.has(properties.buttonStyle) ? properties.buttonStyle : "bordered";
        node.className = `aui-button aui-button-${style}`;
        if (properties.role === "destructive") node.classList.add("aui-button-destructive");

        // Leading icon (systemImage / materialName:web; assetImage warns-and-skips)
        // through the shared glyph seam — the same path as Image.
        const icon = labelIcon(selectLabelIcon(properties, "assetImage", "Button", ctx.logger),
            properties, "Button", ctx.logger);
        const title = properties.title ?? "";
        if (icon) {
            node.classList.add("aui-button-has-icon");
            node.appendChild(icon);
        }
        if (title) {
            const label = document.createElement("span");
            label.className = "aui-button-title";
            label.textContent = title;
            node.appendChild(label);
        }

        if (typeof properties.actionID === "string") {
            markHandlesAction(node);
            node.addEventListener("click", () => {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, {
                    title: properties.title ?? "",
                });
            });
        }
        return node;
    },
});
