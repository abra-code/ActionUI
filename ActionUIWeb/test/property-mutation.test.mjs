// Tests for the runtime property bridge:
//   - ModifierResolver.applyElementProperty  (the per-property appliers)
//   - ActionUIModel.setElementProperty       (find node -> apply -> record override)
// Reconstructs the assertions recorded in Private/Commit_Notes_Web_SetElementProperty.md
// and the scaleEffect/rotationEffect part of Private/Commit_Notes_Web_Animation.md.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { applyElementProperty } from "../src/Common/ModifierResolver.js";
import { ActionUIModel } from "../src/Common/ActionUIModel.js";
// Importing the Picker view registers its runtime "options" applier (a view module
// contributing to setElementProperty via registerElementPropertyApplier).
import "../src/Views/Picker.js";

test("opacity / hidden / cornerRadius / help set the right styles, hidden bidirectionally", () => {
    const logger = makeLogger();
    const n = makeElement();
    assert.equal(applyElementProperty(n, "opacity", 0.3, logger), true);
    assert.equal(n.style.opacity, "0.3");

    applyElementProperty(n, "hidden", true, logger);
    assert.equal(n.style.display, "none");
    applyElementProperty(n, "hidden", false, logger);
    assert.equal(n.style.display, "", "hidden:false restores display (bidirectional)");

    applyElementProperty(n, "cornerRadius", 8, logger);
    assert.equal(n.style.borderRadius, "8px");
    assert.equal(n.style.overflow, "hidden");

    applyElementProperty(n, "help", "hi", logger);
    assert.equal(n.title, "hi");
    assert.equal(logger.warningCount(), 0);
});

test("disabled toggles class + property both ways", () => {
    const logger = makeLogger();
    const n = makeElement();
    applyElementProperty(n, "disabled", true, logger);
    assert.ok(n.classList.contains("aui-disabled"));
    assert.equal(n.disabled, true);
    applyElementProperty(n, "disabled", false, logger);
    assert.equal(n.classList.contains("aui-disabled"), false);
    assert.equal(n.disabled, false);
});

test("color properties: foregroundStyle sets color, foregroundColor is retired, invalid resets + warns", () => {
    const logger = makeLogger();
    const n = makeElement();
    applyElementProperty(n, "foregroundStyle", "#00ff00", logger);
    assert.equal(n.style.color, "#00ff00");
    applyElementProperty(n, "background", "#0000ff", logger);
    assert.equal(n.style.backgroundColor, "#0000ff");
    assert.equal(logger.warningCount(), 0);

    // foregroundColor is the retired SwiftUI name (Apple/Android only honor foregroundStyle);
    // it is no longer a recognized property.
    assert.equal(applyElementProperty(n, "foregroundColor", "#ff0000", logger), false);
    assert.ok(logger.warned("not a host-settable visual property"));

    applyElementProperty(n, "background", "notacolor", logger);
    assert.equal(n.style.backgroundColor, "", "an unresolvable color resets to default");
    assert.ok(logger.warned("Unknown color"));
});

test("scaleEffect / rotationEffect map to the independent CSS scale / rotate, reset on non-number", () => {
    const logger = makeLogger();
    const n = makeElement();
    assert.equal(applyElementProperty(n, "scaleEffect", 1.5, logger), true);
    assert.equal(n.style.scale, "1.5");
    applyElementProperty(n, "scaleEffect", "x", logger);
    assert.equal(n.style.scale, "", "non-number scaleEffect resets");

    assert.equal(applyElementProperty(n, "rotationEffect", 90, logger), true);
    assert.equal(n.style.rotate, "90deg");
    applyElementProperty(n, "rotationEffect", "x", logger);
    assert.equal(n.style.rotate, "", "non-number rotationEffect resets");
});

test("an unsupported property returns false and warns", () => {
    const logger = makeLogger();
    const n = makeElement();
    assert.equal(applyElementProperty(n, "text", "hello", logger), false);
    assert.ok(logger.warned("not a host-settable visual property"));
});

test("Picker 'options' applier rebuilds a menu <select>'s options, preserving a surviving selection", () => {
    installDom();
    const logger = makeLogger();
    const select = makeElement("select");
    // Seed it as a length menu, "L3" selected.
    for (const [title, tag] of [["meter", "L0"], ["inch", "L3"]]) {
        const opt = makeElement("option");
        opt.value = tag;
        opt.textContent = title;
        select.appendChild(opt);
    }
    select.value = "L3";

    // Repopulate to a different category: the old selection is gone, so it falls to
    // the first new option.
    assert.equal(
        applyElementProperty(select, "options",
            [{ title: "Celsius", tag: "T0" }, { title: "Kelvin", tag: "T2" }], logger),
        true,
    );
    assert.deepEqual(select.children.map((o) => o.value), ["T0", "T2"]);
    assert.equal(select.value, "T0", "a dropped selection falls to the first option");
    assert.equal(logger.warningCount(), 0);

    // A repopulation that still contains the current selection keeps it.
    select.value = "T2";
    applyElementProperty(select, "options",
        [{ title: "Celsius", tag: "T0" }, { title: "Fahrenheit", tag: "T1" }, { title: "Kelvin", tag: "T2" }], logger);
    assert.equal(select.value, "T2", "a surviving selection is preserved");
});

test("Picker 'options' applier warns and no-ops on a non-menu node", () => {
    const logger = makeLogger();
    const fieldset = makeElement("fieldset"); // radioGroup / segmented skin
    assert.equal(applyElementProperty(fieldset, "options", [{ title: "x", tag: "1" }], logger), true);
    assert.ok(logger.warned("only for a menu-style Picker"));
});

test("ActionUIModel.setElementProperty applies to the node by id and records the override", () => {
    installDom();
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const node = makeElement();
    model.findNode = (id) => (id === 5 ? node : null);

    model.setElementProperty(5, "opacity", 0.7);
    assert.equal(node.style.opacity, "0.7");
    assert.equal(model.propertyOverrides.get(5).opacity, 0.7, "override recorded per id");

    model.setElementProperty(999, "opacity", 0.1);
    assert.ok(logger.warned("no element with id 999"));

    model.setElementProperty(5, "frame", {});
    assert.equal(model.propertyOverrides.get(5).frame, undefined, "an unsupported name is not recorded");
    assert.ok(logger.warned("not a host-settable"));

    model.cleanupElement(5);
    assert.equal(model.propertyOverrides.get(5), undefined, "cleanupElement clears the overrides");
});
