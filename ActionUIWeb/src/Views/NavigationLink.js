// NavigationLink.js — NavigationLink element.
// Web analog of ActionUI/Views/NavigationLink.swift (and ActionUIAndroid
// Views/NavigationLink.kt).
//
// A push trigger: a tappable title row that asks the enclosing NavigationStack
// to push a destination. SwiftUI hands the push through the environment;
// Android through a LocalNavPush CompositionLocal. The web's ambient equivalent
// is **DOM event bubbling**: a tap dispatches a bubbling `aui-nav-push` custom
// event whose `detail` is the target id, caught by the nearest enclosing
// NavigationStack (NavigationStack.js, NAV_PUSH_EVENT).
//
// Target resolution (mirrors resolveLinkTarget in NavigationLink.kt):
//   * an inline `destination` view (Form 1) — pushes that view, which the
//     enclosing NavigationStack has hoisted into its id-keyed registry by its
//     `id`. The inline destination must carry an `id` to be addressable (the
//     same constraint as Android's NavHost; SwiftUI alone needs no id).
//   * `destinationViewId` (Int, Form 2 by-reference) — pushes the parent
//     NavigationStack's `destinations[]` entry with that id.
// An inline destination wins when both are present, matching the Apple schema.
//
// Rendering mirrors Label/Button: an optional leading icon through the shared
// glyph seam (`systemImage` / `materialName:web`), the `title` (default "Link"),
// and a trailing chevron tap affordance.
//
// Degrades vs. Apple: outside a NavigationStack the bubbling event reaches no
// handler (a no-op); a link with no resolvable target warns on tap.

import { register } from "../Common/ActionUIRegistry.js";
import { selectLabelIcon, labelIcon } from "../Helpers/SymbolIcon.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

// Must match NavigationStack.js. A bubbling CustomEvent whose detail is the
// target destination id.
export const NAV_PUSH_EVENT = "aui-nav-push";

register("NavigationLink", {
    valueType: "none",

    // Mirrors NavigationLink.swift validateProperties (only `title` here;
    // destinationViewId is a base View property elsewhere).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log(`Invalid type for NavigationLink title: expected String, got ${typeof validated.title}, ignoring`, "warning");
            delete validated.title;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("button");
        node.type = "button";
        node.className = "aui-nav-link";

        const title = typeof properties.title === "string" ? properties.title : "Link";

        // Inline destination (Form 1) wins over destinationViewId (Form 2). The
        // inline view is built by the enclosing NavigationStack, not here — this
        // link only needs its id to address the push.
        const inlineDest = element.destination();
        const target = (inlineDest && inlineDest.id > 0)
            ? inlineDest.id
            : (Number.isInteger(properties.destinationViewId) ? properties.destinationViewId : null);

        const icon = labelIcon(
            selectLabelIcon(properties, "imageName", "NavigationLink", ctx.logger),
            properties, "NavigationLink", ctx.logger,
        );
        if (icon) {
            node.classList.add("aui-nav-link-has-icon");
            node.appendChild(icon);
        }

        const titleSpan = document.createElement("span");
        titleSpan.className = "aui-nav-link-title";
        titleSpan.textContent = title;
        node.appendChild(titleSpan);

        const chevron = document.createElement("span");
        chevron.className = "aui-nav-link-chevron";
        chevron.textContent = "›"; // ›
        node.appendChild(chevron);

        // The push is the link's behavior, so opt out of the generic actionID
        // click handler (a NavigationLink's tap navigates, it does not fire an
        // action) — the same markHandlesAction stance the inputs take.
        markHandlesAction(node);
        node.addEventListener("click", () => {
            if (target === null) {
                ctx.logger.log(`NavigationLink '${title}' has no destinationViewId or id-bearing inline destination`, "warning");
                return;
            }
            node.dispatchEvent(new CustomEvent(NAV_PUSH_EVENT, { detail: target, bubbles: true }));
        });

        return node;
    },
});
