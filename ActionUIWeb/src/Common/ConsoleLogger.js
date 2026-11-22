// ConsoleLogger.js — console-backed ActionUILogger.
// Web analog of ActionUI/Common/ActionUILogger.swift + ConsoleLogger.swift (PoC subset).
// Levels, most to least important: "error", "warning", "info", "debug", "verbose".
//
// By default only warnings and errors are printed, as Apple's and Android's release builds do:
// the other levels name properties, values and addresses that a page's console should not
// show to whoever opens it. A host that wants more passes { maxLevel: "info" } (or "debug",
// "verbose"), or installs its own logger.

const LEVELS = ["error", "warning", "info", "debug", "verbose"];

export class ConsoleLogger {
    constructor({ maxLevel = "warning" } = {}) {
        const rank = LEVELS.indexOf(maxLevel);
        this.maxRank = rank >= 0 ? rank : LEVELS.indexOf("warning");
    }

    log(message, level = "info") {
        const rank = LEVELS.indexOf(level);
        // An unknown level counts as info.
        if ((rank >= 0 ? rank : LEVELS.indexOf("info")) > this.maxRank) return;
        const line = `ActionUI [${level}]: ${message}`;
        if (level === "error") console.error(line);
        else if (level === "warning") console.warn(line);
        else console.log(line);
    }
}
