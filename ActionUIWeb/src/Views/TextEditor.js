// TextEditor.js — TextEditor element.
// Web analog of ActionUI/Views/TextEditor.swift (and ActionUIAndroid
// Views/TextEditor.kt).
//
// A multi-line text editor with an automatic internal scroller, rendered as a
// native <textarea> in the shared TextField box. The height comes from the
// inherited frame.height when supplied; otherwise theme.css applies a default
// so there is always something to scroll within (the Android stance — SwiftUI's
// TextEditor is sized by its container). `placeholder` maps to the native
// placeholder attribute (Apple draws an overlay; same effect). `readOnly` makes
// the text selectable/scrollable but not editable — distinct from `disabled`,
// which blocks all interaction; programmatic setValue still works either way.
//
// `markdown` (attributed editing, macOS/iOS 26+) is deferred like Android:
// its raw string renders as plain editable text with a warning, and `text`
// wins when both are present (on the attributed platforms markdown takes
// precedence — see Web_Porting_Notes.md). valueChangeActionID fires on every
// user edit; programmatic setValue is silent, mirroring the Apple container's
// suppression of its own model echoes.
// Observable value: the editor's plain-text string.

import { register } from "../Common/ActionUIRegistry.js";

register("TextEditor", {
    valueType: "string",

    // Mirrors TextEditor.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.text !== undefined && typeof validated.text !== "string") {
            logger.log("TextEditor text must be a String; ignoring", "warning");
            delete validated.text;
        }
        if (validated.placeholder !== undefined && typeof validated.placeholder !== "string") {
            logger.log("TextEditor placeholder must be a String; defaulting to nil", "warning");
            delete validated.placeholder;
        }
        if (validated.markdown !== undefined && typeof validated.markdown !== "string") {
            logger.log("TextEditor markdown must be a String; ignoring", "warning");
            delete validated.markdown;
        }
        if (validated.text !== undefined && validated.markdown !== undefined) {
            logger.log("TextEditor has both text and markdown; markdown takes precedence", "warning");
        }
        return validated;
    },

    // `text` wins, then the raw `markdown` string, then "" — the Android
    // textEditorInitialValue order for the non-attributed platforms.
    initialValue: (element, properties) => properties.text ?? properties.markdown ?? "",

    buildView: (element, properties, ctx) => {
        const textarea = document.createElement("textarea");
        textarea.className = "aui-textfield aui-texteditor";
        textarea.value = properties.text ?? properties.markdown ?? "";
        if (properties.markdown !== undefined) {
            ctx.logger.log(
                "TextEditor 'markdown' (attributed editing) is not supported on web; showing it as plain text",
                "warning",
            );
        }
        if (properties.placeholder) textarea.placeholder = properties.placeholder;
        if (properties.readOnly === true) textarea.readOnly = true;

        textarea.addEventListener("input", () => {
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        });

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => textarea.value,
                // Programmatic changes are silent (no valueChangeActionID), as
                // on Apple, where the container suppresses its own model echoes.
                setValue: (value) => { textarea.value = String(value); },
            });
        }
        return textarea;
    },
});
