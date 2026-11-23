// The console logger prints warnings and errors by default, more only when the host asks.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ConsoleLogger } from "../src/Common/ConsoleLogger.js";

function capture(fn) {
    const lines = [];
    const saved = { log: console.log, warn: console.warn, error: console.error };
    console.log = (line) => lines.push(["log", line]);
    console.warn = (line) => lines.push(["warn", line]);
    console.error = (line) => lines.push(["error", line]);
    try { fn(); } finally { Object.assign(console, saved); }
    return lines;
}

test("by default only warnings and errors are printed", () => {
    const logger = new ConsoleLogger();
    const lines = capture(() => {
        for (const level of ["error", "warning", "info", "debug", "verbose", "unknown"]) logger.log(level, level);
        logger.log("no level");
    });
    assert.deepEqual(lines, [["error", "ActionUI [error]: error"], ["warn", "ActionUI [warning]: warning"]]);
});

test("a host can ask for more, up to the level it names", () => {
    const lines = capture(() => {
        const logger = new ConsoleLogger({ maxLevel: "debug" });
        for (const level of ["error", "warning", "info", "debug", "verbose"]) logger.log(level, level);
    });
    assert.deepEqual(lines.map(([, line]) => line), ["ActionUI [error]: error", "ActionUI [warning]: warning",
                                                      "ActionUI [info]: info", "ActionUI [debug]: debug"]);
});

test("an unknown maximum level keeps the default", () => {
    const lines = capture(() => new ConsoleLogger({ maxLevel: "everything" }).log("hidden", "info"));
    assert.deepEqual(lines, []);
});
