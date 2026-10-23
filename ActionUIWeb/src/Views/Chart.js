// Chart.js — Chart element on the web: a "Chart Unavailable" placeholder.
// Apple draws the element with Swift Charts (ActionUI/Views/Chart.swift); the web
// has no chart renderer, so it draws the ContentUnavailableView look in the chart's
// place, sized by the element's own frame and padding, and logs one warning per page.
// Android does the same (ActionUIAndroid Views/Chart.kt).
//
// The model keeps the parts of the Apple contract a host relies on: the value is a
// string (the selection as JSON, "" when nothing is selected; the user cannot change
// it here), the rows (the "content" state) take the rows API, and
// setElementProperty(id, "chart", ...) is accepted without a warning. The description
// is not read: its inline "data" does not become the rows, and no action fires.

import { getConstruction, register } from "../Common/ActionUIRegistry.js";
import { registerElementPropertyApplier } from "../Common/ModifierResolver.js";
import "./ContentUnavailableView.js";

export const CHART_PLACEHOLDER = Object.freeze({
    title: "Chart Unavailable",
    description: "Charts are not supported on this platform.",
    systemImage: "chart.bar",
});

let warned = false;

register("Chart", {
    valueType: "string",

    validateProperties: (properties) => ({ ...properties }),

    initialValue: () => "",

    initialStates: () => ({ content: [] }),

    buildView: (element, properties, ctx) => {
        if (!warned) {
            warned = true;
            ctx.logger.log("Chart is not supported on the web; drawing a placeholder in its place", "warning");
        }
        // Id 0: the placeholder binds nothing, so it shows its own title, not the chart's value.
        const node = getConstruction("ContentUnavailableView").buildView(
            { id: 0, type: "ContentUnavailableView", properties: CHART_PLACEHOLDER }, CHART_PLACEHOLDER, ctx);
        // The look only: a chart is not held to ContentUnavailableView's 400 width.
        node.classList.remove("aui-cap-width");
        node.style.maxWidth = "";
        delete node.auiWidthCap;
        if (element.id > 0) {
            let value = "";
            let rows = [];
            ctx.model.bind(element.id, {
                getValue: () => value,
                setValue: (newValue) => { value = String(newValue ?? ""); },
            });
            ctx.model.bindState(element.id, {
                getState: (key) => (key === "content" ? rows : undefined),
                setState: (key, newValue) => { if (key === "content") rows = Array.isArray(newValue) ? newValue : []; },
            });
        }
        return node;
    },
});

// A replaced description has nothing to redraw here; accept it as a property set.
registerElementPropertyApplier("chart", (node, value, logger) => {
    if (node?.dataset?.auiType !== "Chart") {
        logger.log("setElementProperty 'chart' applies only to a Chart; ignored", "warning");
    }
});
