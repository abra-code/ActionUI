// ContentUnavailableView.js — ContentUnavailableView element.
// Web analog of ActionUI/Views/ContentUnavailableView.swift and ActionUIAndroid
// Views/ContentUnavailableView.kt.
//
// The standard empty-state view: a centered hero glyph over a bold title and an
// optional secondary description - SwiftUI's ContentUnavailableView. The web
// renders real icons (the shared SymbolIcon glyph seam), where Android downgrades
// the icon to text on its asset path; the web already has the glyph path.
//
// Properties (ContentUnavailableView.swift):
//   title       String (the primary message; default "No Content")
//   systemImage String SF Symbol (default "exclamationmark.triangle" when absent,
//               mirroring Swift's fallback Label icon)
//   description String (secondary text; omitted when absent)
//   search      Bool - the built-in search appearance (magnifyingglass +
//               "No Results"); when true, title/systemImage/description are ignored
//   query       String - the search term shown in the message
//
// Value bridge (Apple's, valueType "string"): the runtime value is the title
// (non-search) or the query (search). get/setElementValue round-trips it; a host
// setString("planets") on a search view re-renders it as "No Results for ...".

import { register } from "../Common/ActionUIRegistry.js";
import { systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

register("ContentUnavailableView", {
    valueType: "string",

    // Mirrors ContentUnavailableView.swift validateProperties (verbatim warnings).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("ContentUnavailableView title must be a String; ignoring", "warning");
            delete validated.title;
        }
        if (validated.systemImage !== undefined && typeof validated.systemImage !== "string") {
            logger.log("ContentUnavailableView systemImage must be a String; ignoring", "warning");
            delete validated.systemImage;
        }
        if (validated.description !== undefined && typeof validated.description !== "string") {
            logger.log("ContentUnavailableView description must be a String; ignoring", "warning");
            delete validated.description;
        }
        if (validated.search !== undefined && typeof validated.search !== "boolean") {
            logger.log("ContentUnavailableView search must be a Boolean; ignoring", "warning");
            delete validated.search;
        }
        if (validated.query !== undefined && typeof validated.query !== "string") {
            logger.log("ContentUnavailableView query must be a String; ignoring", "warning");
            delete validated.query;
        }
        return validated;
    },

    // The runtime value: the query in search mode, otherwise the title.
    initialValue: (element, properties) => {
        if (properties.search === true) return properties.query ?? "";
        return properties.title ?? "No Content";
    },

    buildView: (element, properties, ctx) => {
        const isSearch = properties.search === true;
        const node = document.createElement("div");
        node.className = "aui-content-unavailable";

        const render = (value) => {
            node.replaceChildren();
            const glyphName = isSearch ? "magnifyingglass"
                : (typeof properties.systemImage === "string" ? properties.systemImage : "exclamationmark.triangle");
            const glyph = systemSymbolGlyph(glyphName, { imageScale: "large" }, ctx.logger, (n) =>
                `ContentUnavailableView systemImage '${n}' has no SF->Material mapping; icon omitted.`);
            glyph.classList.add("aui-content-unavailable-icon");
            node.appendChild(glyph);

            const title = document.createElement("span");
            title.className = "aui-content-unavailable-title";
            const description = document.createElement("span");
            description.className = "aui-content-unavailable-description";

            if (isSearch) {
                const query = String(value ?? "");
                title.textContent = "No Results";
                description.textContent = query.length > 0
                    ? `No results for "${query}". Check the spelling or try a new search.`
                    : "Check the spelling or try a new search.";
            } else {
                title.textContent = String(value ?? "") || "No Content";
                if (typeof properties.description === "string") {
                    description.textContent = properties.description;
                }
            }

            node.appendChild(title);
            if (description.textContent) node.appendChild(description);
        };

        const initial = isSearch ? (properties.query ?? "") : (properties.title ?? "No Content");
        let current = initial;
        render(current);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => current,
                setValue: (value) => { current = String(value ?? ""); render(current); },
            });
        }
        return node;
    },
});
