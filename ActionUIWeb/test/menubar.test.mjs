// Tests for the application menu-bar parser (src/Scenes/MenuBar.js parseMenuBar).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLogger } from "./dom-stub.mjs";
import { parseMenuBar } from "../src/Scenes/MenuBar.js";

test("a non-array menu bar warns and yields empty sections", () => {
    const logger = makeLogger();
    const out = parseMenuBar({ not: "an array" }, logger);
    assert.deepEqual(out.sections, []);
    assert.equal(out.account, null);
    assert.ok(logger.warned("must be a JSON array"));
});

test("a CommandMenu becomes a named section of its actionID-bearing items", () => {
    const raw = [{
        type: "CommandMenu",
        properties: { name: "Go" },
        children: [
            { type: "Button", properties: { title: "Overview", actionID: "go.overview" } },
            { type: "Button", properties: { title: "Controls", actionID: "go.controls" } },
        ],
    }];
    const { sections } = parseMenuBar(raw, makeLogger());
    const go = sections.find((s) => s.title === "Go");
    assert.ok(go, "a 'Go' section exists");
    assert.equal(go.items.length, 2);
    assert.equal(go.items[0].title, "Overview");
    assert.equal(go.items[0].actionID, "go.overview");
});

test("a CommandMenu without a name is skipped with a warning", () => {
    const logger = makeLogger();
    const { sections } = parseMenuBar([{ type: "CommandMenu", properties: {}, children: [] }], logger);
    assert.equal(sections.length, 0);
    assert.ok(logger.warned("requires a non-empty 'name'"));
});

test('a role:web "account" CommandMenu routes to the account menu, not a section', () => {
    const raw = [{
        type: "CommandMenu",
        properties: { name: "Account", role: "account", systemImage: "person.crop.circle" },
        children: [{ type: "Button", properties: { title: "Sign out", actionID: "signout" } }],
    }];
    const { sections, account } = parseMenuBar(raw, makeLogger());
    assert.equal(sections.length, 0, "the account menu is not a drawer section");
    assert.ok(account);
    assert.equal(account.title, "Account");
    assert.equal(account.systemImage, "person.crop.circle");
    assert.equal(account.items[0].actionID, "signout");
});
