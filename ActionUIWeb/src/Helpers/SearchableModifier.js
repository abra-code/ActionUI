// SearchableModifier.js — the `searchable` property modifier (List / NavigationStack).
// Web analog of Apple's SearchableModifierView (ActionUI/Helpers/SearchableHelper.swift)
// and ActionUIAndroid's BuildViewWithSearchable. Part of the build pipeline:
// buildElementView calls wrapWithSearchable after the decoration wrap and before the
// toolbar wrap, so the field sits below the navigation title and above the list
// content (the iOS placement). A no-op unless the element declares a valid
// `searchable` property.
//
//   "searchable": { "actionID": <required String>, "prompt": <optional String> }
//
// surfaces a search field whose query is emitted to `actionID` on every change (the
// query string as the action context), so the host filters its data and re-pushes
// rows. The field is a native <input type="search"> — the platform search control,
// with the browser's own clear (×) affordance and search semantics — fronted by a
// leading Material Symbols magnifier, the same icon language the rest of the UI uses.
// The query is locally owned (not bridged to the host value API; the host drives off
// the emitted `actionID`), matching Apple's @State.
//
// Placement is the platform idiom, not a port: SwiftUI floats the field into the
// nearest navigation bar; on web (a desktop target, like macOS) an inline field
// pinned above the list is the idiomatic equivalent, and the emit contract is the
// same either way.

import { materialNameGlyph } from "./SymbolIcon.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

// Reads + validates `searchable`, the read-time mirror of Apple's validateProperties
// searchable block (View.swift): a dictionary with a non-empty String `actionID`
// (else the whole modifier drops with a warning) and an optional String `prompt`
// (a present non-String prompt drops with a warning, the rest kept). Returns null
// when absent or invalid, so the caller falls through to the unwrapped node.
function resolveSearchable(searchable, logger) {
    if (searchable === undefined || searchable === null) return null;
    if (typeof searchable !== "object" || Array.isArray(searchable)) {
        logger.log(`Invalid type for searchable: expected dictionary, got ${typeof searchable}, ignoring`, "warning");
        return null;
    }
    const actionID = searchable.actionID;
    if (typeof actionID !== "string" || actionID.length === 0) {
        logger.log("Invalid searchable: requires a non-empty String 'actionID', ignoring", "warning");
        return null;
    }
    let prompt = null;
    if (searchable.prompt !== undefined) {
        if (typeof searchable.prompt === "string") prompt = searchable.prompt;
        else logger.log("Invalid searchable.prompt: expected String, dropping prompt", "warning");
    }
    return { actionID, prompt };
}

// Wraps bodyNode with a search field above it when the element declares a valid
// `searchable`; otherwise returns bodyNode unchanged. The carrier's data-aui-id
// stays on the inner node (host addressing is unaffected), like the toolbar wrap.
export function wrapWithSearchable(bodyNode, element, properties, ctx) {
    const config = resolveSearchable(properties.searchable, ctx.logger);
    if (!config) return bodyNode;

    const host = document.createElement("div");
    host.className = "aui-searchable";

    // <label> so a click on the magnifier focuses the field.
    const bar = document.createElement("label");
    bar.className = "aui-search-bar";

    const icon = materialNameGlyph("search", {});
    icon.classList.add("aui-search-icon");
    icon.setAttribute("aria-hidden", "true");

    const input = document.createElement("input");
    input.type = "search";
    input.className = "aui-search-field";
    // Mobile soft-keyboard hygiene for a search field (its semantics are intrinsic,
    // not author-declared): a search-optimized keyboard with a "search" return key,
    // and no auto-capitalize / correct / spellcheck mangling the query.
    input.inputMode = "search";
    input.enterKeyHint = "search";
    input.autocapitalize = "none";
    input.setAttribute("autocorrect", "off"); // Safari-only attribute, no IDL property
    input.spellcheck = false;
    if (config.prompt) input.placeholder = config.prompt;
    markHandlesAction(input); // wires its own action; opt out of the generic click handler
    // Emit the query on every change (user types or clears), the query string as the
    // action context — Apple's onChange(of: query).
    input.addEventListener("input", () => {
        ctx.model.dispatchAction(config.actionID, element.id, 0, input.value);
    });

    bar.append(icon, input);
    host.append(bar, bodyNode);
    return host;
}
