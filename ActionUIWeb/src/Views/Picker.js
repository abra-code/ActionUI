// Picker.js — Picker element.
// Web analog of ActionUI/Views/Picker.swift (and ActionUIAndroid Views/Picker.kt).
//
// A single-selection control over a list of tagged options, rendered as a native
// <select>. valueType is "string": the selected option's tag is the value, so a
// host reads/writes the selection with get/setString(id).
//
// Properties (mirroring Picker.swift):
//   title    String label, shown (Form-style) to the left when present.
//   options  Required. Either a simple [String] (titles only; tags are the
//            1-based index as a String — "1", "2", …) or an array of
//            { title, tag } dictionaries for explicit tags. The dictionary form
//            may also include { "section": "Name" } headers and { "divider": true }
//            separators to group items (parsed for parity; titled groups render as
//            <optgroup>).
//   pickerStyle  "menu" | "segmented" | "radioGroup" (the macOS set, matching the
//            macOS-flavored default skin); "wheel" warns as unavailable.
//            "radioGroup" renders a native <fieldset> of <input type="radio">;
//            "segmented" renders the same radios as a joined button bar; "menu"
//            (and the "wheel" fallback) render the native <select> dropdown.
//   horizontalRadioGroupLayout  Bool; lays a radioGroup out in a row instead of a
//            column (only meaningful with pickerStyle "radioGroup").
//   actionID dispatched on user-initiated selection change only (the native
//            `change` event), matching the Apple binding setter; the selected tag
//            is passed as context. Programmatic setString is silent.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

// The macOS-valid styles (the web's default skin is macOS-flavored). "wheel" is
// iOS/visionOS-only, so it warns here as it does on macOS.
const VALID_STYLES = ["menu", "segmented", "radioGroup"];

register("Picker", {
    valueType: "string",

    // Mirrors Picker.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // options: must be [String] or an array of dictionaries, else dropped.
        if (validated.options !== undefined && !isStringArray(validated.options) && !isDictArray(validated.options)) {
            logger.log("Picker 'options' must be [String] or [[\"title\": String, \"tag\": String]]; setting to nil", "warning");
            delete validated.options;
        }

        // pickerStyle: must be valid on this platform, else dropped.
        if (typeof validated.pickerStyle === "string" && !VALID_STYLES.includes(validated.pickerStyle)) {
            logger.log(`Picker style '${validated.pickerStyle}' invalid on this platform; setting to nil`, "warning");
            delete validated.pickerStyle;
        }

        // title: must be a String, else dropped.
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("Picker 'title' must be String; setting to nil", "warning");
            delete validated.title;
        }

        return validated;
    },

    // The selection defaults to the first option's tag (the host can preselect
    // another with setString after the window is presented).
    initialValue: (element, properties) => {
        const first = extractOptions(properties.options).find(() => true);
        return first ? first.tag : undefined;
    },

    buildView: (element, properties, ctx) => {
        const sections = extractSections(properties.options, ctx.logger);
        const allItems = sections.flatMap((section) => section.items);
        const initial = allItems.length ? allItems[0].tag : "";

        // radioGroup is the one style that renders a distinct native control: a
        // <fieldset> of <input type="radio">. Every other style uses the <select>.
        if (properties.pickerStyle === "radioGroup") {
            return buildRadioGroup(element, properties, ctx, sections, initial);
        }

        // segmented is the same radio mechanism styled as a joined button bar —
        // the native, no-infra analog of SwiftUI's .segmented, and a closer
        // fallback than the menu dropdown. Segmented controls are flat, so any
        // sections/dividers collapse into one row of segments.
        if (properties.pickerStyle === "segmented") {
            return buildSegmented(element, properties, ctx, allItems, initial);
        }

        const select = document.createElement("select");
        select.className = "aui-picker";
        if (typeof properties.pickerStyle === "string") {
            select.dataset.auiPickerStyle = properties.pickerStyle;
        }

        // A titled group becomes an <optgroup>; untitled groups (the implicit
        // ungrouped section, or one created by a {"divider": true}) emit their
        // options directly. SwiftUI groups via Section; the native dropdown is the
        // baseline rendering — segmented/radio visuals are deferred skin work.
        const useSections = sections.length > 1 || sections.some((section) => section.title);
        for (const section of sections) {
            const parent = (useSections && section.title)
                ? select.appendChild(makeOptGroup(section.title))
                : select;
            for (const item of section.items) {
                parent.appendChild(makeOption(item));
            }
        }

        select.value = initial;

        markHandlesAction(select);
        // `change` on a <select> fires only on user interaction (a programmatic
        // value assignment does not), so this matches the Apple binding setter,
        // which dispatches actionID on user changes only.
        select.addEventListener("change", () => {
            if (typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id, 0, select.value);
            }
        });

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => select.value,
                setValue: (value) => { select.value = String(value); }, // programmatic: silent
            });
        }

        // Optional leading label, shown when "title" is present (Form-style),
        // reusing the shared labeled-field layout.
        if (properties.title) {
            const wrapper = document.createElement("label");
            wrapper.className = "aui-labeled-field";
            const label = document.createElement("span");
            label.className = "aui-field-label";
            label.textContent = properties.title;
            wrapper.append(label, select);
            return wrapper;
        }
        return select;
    },
});

function makeOption({ title, tag }) {
    const option = document.createElement("option");
    option.value = tag;
    option.textContent = title;
    return option;
}

// Radios are grouped by a shared `name`; each Picker needs a unique one so two
// radioGroup Pickers on a page don't become one mutually-exclusive set.
let radioGroupCounter = 0;

// Builds the radioGroup pickerStyle: a native <fieldset> whose <legend> is the
// Picker title and whose options are <input type="radio"> sharing one `name`.
// Radios have no native <optgroup>; a titled section becomes a sub-heading and a
// divider/untitled break becomes an <hr>. The value is still the selected tag, so
// the binding and actionID wiring match the <select> path.
function buildRadioGroup(element, properties, ctx, sections, initial) {
    const fieldset = document.createElement("fieldset");
    fieldset.className = "aui-picker-radio";
    if (properties.horizontalRadioGroupLayout === true) {
        fieldset.classList.add("aui-picker-radio-horizontal");
    }
    if (properties.title) {
        const legend = document.createElement("legend");
        legend.className = "aui-picker-legend";
        legend.textContent = properties.title;
        fieldset.appendChild(legend);
    }

    const groupName = `aui-picker-radio-${++radioGroupCounter}`;
    const inputs = [];
    const useSections = sections.length > 1 || sections.some((section) => section.title);

    sections.forEach((section, index) => {
        if (useSections) {
            if (section.title) {
                const heading = document.createElement("span");
                heading.className = "aui-radio-section-title";
                heading.textContent = section.title;
                fieldset.appendChild(heading);
            } else if (index > 0) {
                // A divider-created or implicit untitled break after the first group.
                const rule = document.createElement("hr");
                rule.className = "aui-radio-divider";
                fieldset.appendChild(rule);
            }
        }
        for (const item of section.items) {
            const label = document.createElement("label");
            label.className = "aui-radio";
            const input = document.createElement("input");
            input.type = "radio";
            input.name = groupName;
            input.value = item.tag;
            if (item.tag === initial) input.checked = true;
            const text = document.createElement("span");
            text.textContent = item.title;
            label.append(input, text);
            fieldset.appendChild(label);
            inputs.push(input);
        }
    });

    const selectedValue = () => {
        const checked = inputs.find((input) => input.checked);
        return checked ? checked.value : "";
    };

    markHandlesAction(fieldset);
    // `change` bubbles from the chosen radio and fires only on user interaction
    // (setting .checked programmatically does not), matching the binding setter.
    fieldset.addEventListener("change", () => {
        if (typeof properties.actionID === "string") {
            ctx.model.dispatchAction(properties.actionID, element.id, 0, selectedValue());
        }
    });

    if (element.id > 0) {
        ctx.model.bind(element.id, {
            getValue: () => selectedValue(),
            setValue: (value) => { // programmatic: silent (no change event)
                const tag = String(value);
                for (const input of inputs) input.checked = (input.value === tag);
            },
        });
    }
    return fieldset;
}

// Builds the segmented pickerStyle: the same name-grouped <input type="radio">
// mechanism as buildRadioGroup, but laid out as a flat, joined button bar (the
// radios are visually hidden; the labels are the segments). Kept as a separate
// builder — with its own small copy of the binding wiring — so it stays purely
// additive over the radioGroup change. The value is still the selected tag.
function buildSegmented(element, properties, ctx, items, initial) {
    const group = document.createElement("div");
    group.className = "aui-picker-segmented";
    group.setAttribute("role", "radiogroup");
    if (properties.title) group.setAttribute("aria-label", properties.title);

    const groupName = `aui-picker-radio-${++radioGroupCounter}`;
    const inputs = [];
    for (const item of items) {
        const segment = document.createElement("label");
        segment.className = "aui-segment";
        const input = document.createElement("input");
        input.type = "radio";
        input.name = groupName;
        input.value = item.tag;
        if (item.tag === initial) input.checked = true;
        const text = document.createElement("span");
        text.textContent = item.title;
        segment.append(input, text);
        group.appendChild(segment);
        inputs.push(input);
    }

    const selectedValue = () => {
        const checked = inputs.find((input) => input.checked);
        return checked ? checked.value : "";
    };

    markHandlesAction(group);
    group.addEventListener("change", () => {
        if (typeof properties.actionID === "string") {
            ctx.model.dispatchAction(properties.actionID, element.id, 0, selectedValue());
        }
    });

    if (element.id > 0) {
        ctx.model.bind(element.id, {
            getValue: () => selectedValue(),
            setValue: (value) => { // programmatic: silent (no change event)
                const tag = String(value);
                for (const input of inputs) input.checked = (input.value === tag);
            },
        });
    }

    // Optional leading label (a <div>, not a <label>, since it groups several
    // radios), reusing the shared labeled-field layout.
    if (properties.title) {
        const wrapper = document.createElement("div");
        wrapper.className = "aui-labeled-field";
        const label = document.createElement("span");
        label.className = "aui-field-label";
        label.textContent = properties.title;
        wrapper.append(label, group);
        return wrapper;
    }
    return group;
}

function makeOptGroup(label) {
    const group = document.createElement("optgroup");
    group.label = label;
    return group;
}

function isStringArray(value) {
    return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function isDictArray(value) {
    return Array.isArray(value) && value.every(isPlainObject);
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Parses "options" into [{ title, tag, items }] sections, mirroring
// Picker.swift's extractSections. The simple [String] form yields one untitled
// section with 1-based String tags; the dictionary form honors "section"
// headers and "divider" separators and skips malformed items (with a warning).
function extractSections(raw, logger) {
    if (raw === undefined || raw === null) return [];

    // Format 1: simple array of strings → one untitled section, 1-based tags.
    if (isStringArray(raw)) {
        const items = raw.map((title, index) => ({ title, tag: String(index + 1) }));
        return [{ title: null, items }];
    }

    // Format 2: array of dictionaries, possibly with section/divider entries.
    if (isDictArray(raw)) {
        const sections = [];
        let currentTitle = null;
        let currentItems = [];
        let hasSections = false;

        const flush = () => {
            if (currentItems.length || sections.length) {
                sections.push({ title: currentTitle, items: currentItems });
                currentItems = [];
            }
        };

        raw.forEach((dict, index) => {
            // Divider: close the current group and start a new untitled one.
            if (dict.divider === true) {
                hasSections = true;
                flush();
                currentTitle = null;
                return;
            }
            // Section header: close the current group and open a titled one.
            if (typeof dict.section === "string") {
                hasSections = true;
                flush();
                currentTitle = dict.section;
                return;
            }
            // Regular option item.
            if (typeof dict.title !== "string" || dict.title === "") {
                logger?.log(`Picker options[${index}] missing valid 'title'; skipping`, "warning");
                return;
            }
            if (typeof dict.tag !== "string" || dict.tag === "") {
                logger?.log(`Picker options[${index}] missing valid 'tag'; skipping`, "warning");
                return;
            }
            currentItems.push({ title: dict.title, tag: dict.tag });
        });

        if (hasSections) {
            sections.push({ title: currentTitle, items: currentItems });
        } else {
            sections.push({ title: null, items: currentItems });
        }
        return sections;
    }

    logger?.log("Picker 'options' must be [String] or [[\"title\": String, \"tag\": String]]", "warning");
    return [];
}

function extractOptions(raw) {
    return extractSections(raw).flatMap((section) => section.items);
}
