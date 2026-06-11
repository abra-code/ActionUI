// ConsoleLogger.js — console-backed ActionUILogger.
// Web analog of ActionUI/Common/ActionUILogger.swift + ConsoleLogger.swift (PoC subset).
// Levels: "error", "warning", "info".

export class ConsoleLogger {
    log(message, level = "info") {
        const line = `ActionUI [${level}]: ${message}`;
        if (level === "error") console.error(line);
        else if (level === "warning") console.warn(line);
        else console.log(line);
    }
}
