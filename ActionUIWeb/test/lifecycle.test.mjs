// Tests for the page-lifecycle hooks (src/Helpers/LifecycleHooks.js).
// Reconstructs the assertions recorded in Private/Commit_Notes_Web_Lifecycle.md.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";
import { installLifecycleHooks } from "../src/Helpers/LifecycleHooks.js";

function setup() {
    const dom = installDom();
    const logger = makeLogger();
    const dispatched = [];
    const model = { dispatchAction: (...args) => dispatched.push(args) };
    return { dom, logger, dispatched, model };
}

test("the full set wires both listeners and dispatches at viewID 0", () => {
    const { dom, logger, dispatched, model } = setup();
    const cleanup = installLifecycleHooks(
        { onForegroundActionID: "fg", onBackgroundActionID: "bg", onTerminateActionID: "term" },
        model, logger,
    );
    assert.equal(dom.documentListenerCount("visibilitychange"), 1);
    assert.equal(dom.windowListenerCount("pagehide"), 1);

    dom.setVisibility("hidden");
    dom.fireDocument("visibilitychange");
    assert.deepEqual(dispatched.at(-1), ["bg", 0, 0, null], "hidden -> onBackground at viewID 0, no context");

    dom.setVisibility("visible");
    dom.fireDocument("visibilitychange");
    assert.deepEqual(dispatched.at(-1), ["fg", 0, 0, null], "visible -> onForeground");

    dom.fireWindow("pagehide");
    assert.deepEqual(dispatched.at(-1), ["term", 0, 0, null], "pagehide -> onTerminate");

    cleanup();
    assert.equal(dom.documentListenerCount("visibilitychange"), 0, "cleanup removes the visibilitychange listener");
    assert.equal(dom.windowListenerCount("pagehide"), 0, "cleanup removes the pagehide listener");
});

test("absent hooks wire nothing, warn nothing, and still return a cleanup", () => {
    const { dom, logger, model } = setup();
    const cleanup = installLifecycleHooks({ alignment: "leading" }, model, logger);
    assert.equal(dom.documentListenerCount("visibilitychange"), 0);
    assert.equal(dom.windowListenerCount("pagehide"), 0);
    assert.equal(logger.warningCount(), 0);
    assert.equal(typeof cleanup, "function");
});

test("a partial declaration wires only the needed listener", () => {
    const { dom, model, logger } = setup();
    installLifecycleHooks({ onBackgroundActionID: "bg" }, model, logger);
    assert.equal(dom.documentListenerCount("visibilitychange"), 1, "visibilitychange wired for background");
    assert.equal(dom.windowListenerCount("pagehide"), 0, "pagehide not wired without onTerminate");
});

test("a non-string action ID warns and is not wired", () => {
    const { dom, logger, model } = setup();
    installLifecycleHooks({ onTerminateActionID: 42 }, model, logger);
    assert.ok(logger.warned("onTerminateActionID"));
    assert.equal(dom.windowListenerCount("pagehide"), 0);
});
