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
//            macOS-flavored default skin); "wheel" warns as unavailable. The web
//            renders every style as the native dropdown for now — distinct visuals
//            are deferred skin work, tracked in Web_Porting_Notes.md.
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
