// Tests for pull-to-refresh (List / ScrollView with onRefreshActionID), the web
// side of the cross-platform feature (Apple .refreshable / Android PullToRefreshBox):
//   - the pure gesture math (resistedPull / isRefreshPull, src/Helpers/PullToRefreshHelper.js)
//   - the validators dropping a non-string onRefreshActionID (Views/List.js, ScrollView.js)
//   - the model lifecycle (ActionUIModel.beginRefresh / endRefreshTargeting / timeout)
//   - the DOM wiring (wrapWithPullToRefresh: a synthetic pull begins a refresh; onEnd retracts)
//
// As with edge-swipe.test.mjs, the threshold decision - where the gesture is right
// or wrong - is pinned as a pure function; the DOM wiring is exercised with the
// stub's synthetic touch events.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import {
    resistedPull,
    isRefreshPull,
    wrapWithPullToRefresh,
    PULL_THRESHOLD,
    INDICATOR_HEIGHT,
} from "../src/Helpers/PullToRefreshHelper.js";
import { ActionUIModel } from "../src/Common/ActionUIModel.js";

// ---------------- pure gesture math ----------------

test("resistedPull rubber-bands a downward drag and ignores an upward one", () => {
    assert.equal(resistedPull(0), 0, "no pull");
    assert.equal(resistedPull(-50), 0, "an upward drag is not a pull");
    assert.equal(resistedPull(40), 20, "follows the finger at half speed");
    assert.equal(resistedPull(1000), 96, "capped so it cannot grow without bound");
});

test("isRefreshPull arms at the threshold (inclusive) and not below it", () => {
    assert.equal(isRefreshPull(PULL_THRESHOLD), true, `${PULL_THRESHOLD}px arms`);
    assert.equal(isRefreshPull(PULL_THRESHOLD - 1), false, "one px short does not arm");
    assert.equal(isRefreshPull(0), false);
});

// ---------------- validators ----------------

let getConstruction;
before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const validate = (type, props) => {
    const logger = makeLogger();
    return { out: getConstruction(type).validateProperties(props, logger), logger };
};

for (const type of ["List", "ScrollView"]) {
    test(`${type}: a string onRefreshActionID is kept, a non-string is dropped + warned`, () => {
        const kept = validate(type, { onRefreshActionID: "refresh.it" });
        assert.equal(kept.out.onRefreshActionID, "refresh.it");
        assert.equal(kept.logger.warningCount(), 0);

        const dropped = validate(type, { onRefreshActionID: 42 });
        assert.equal(dropped.out.onRefreshActionID, undefined, "non-string dropped");
        assert.ok(dropped.logger.warned("onRefreshActionID must be a string"));
    });

    test(`${type} opts into the refresh wrapper (construction.refreshable)`, () => {
        assert.equal(getConstruction(type).refreshable, true);
    });
}

// ---------------- model lifecycle ----------------

// A model with a captured action dispatcher; rootNode stays null so subtreeIds
// falls back to {viewID} (the List case: a List mutates its own id).
function refreshModel() {
    const m = new ActionUIModel("", makeLogger());
    const fired = [];
    m.actionDispatcher = (actionID, windowUUID, viewID, viewPartID, context) =>
        fired.push({ actionID, viewID, context });
    return { m, fired };
}

test("beginRefresh fires the actionID and holds onEnd until a targeting mutation", () => {
    const { m, fired } = refreshModel();
    let ended = 0;
    m.beginRefresh(5, "list.refresh", () => { ended += 1; });

    assert.deepEqual(fired, [{ actionID: "list.refresh", viewID: 5, context: null }], "fires on begin");
    assert.equal(ended, 0, "indicator stays up until the client delivers data");

    m.setElementValue(5, 0, "x"); // a mutation to the refreshing view ends it
    assert.equal(ended, 1, "delivering data ends the refresh");

    m.setElementValue(5, 0, "y"); // already ended: no second onEnd
    assert.equal(ended, 1, "idempotent - ends exactly once");
});

test("setElementState (the rows API) ends a refresh targeting the view", () => {
    const { m } = refreshModel();
    let ended = 0;
    m.beginRefresh(5, "r", () => { ended += 1; });
    m.setElementState(5, "content", [["fresh"]]);
    assert.equal(ended, 1);
});

test("a mutation outside the captured subtree does not end the refresh", () => {
    const { m } = refreshModel();
    let ended = 0;
    m.beginRefresh(5, "r", () => { ended += 1; }); // subtree {5}
    m.setElementValue(9, 0, "x"); // an unrelated view
    assert.equal(ended, 0);
});

test("a mutation to a descendant ends the refresh (the ScrollView case)", () => {
    const { m } = refreshModel();
    let ended = 0;
    m.beginRefresh(5, "r", () => { ended += 1; });
    m.refreshes.get(5).subtreeIds.add(9); // emulate a captured descendant id (DOM-less here)
    m.setElementState(9, "content", []); // updating the inner content, not the container's own id
    assert.equal(ended, 1);
});

test("the safety timeout ends a refresh the client never signals", async () => {
    const { m } = refreshModel();
    m.refreshTimeoutMs = 15; // lower it for the test
    let ended = 0;
    m.beginRefresh(5, "r", () => { ended += 1; });
    assert.equal(ended, 0, "still up immediately");
    await new Promise((r) => setTimeout(r, 40));
    assert.equal(ended, 1, "timed out and retracted");
});

test("removeElement cleanup clears an in-flight refresh", () => {
    const { m } = refreshModel();
    let ended = 0;
    m.beginRefresh(5, "r", () => { ended += 1; });
    m.cleanupElement(5);
    assert.equal(m.refreshes.has(5), false, "record gone");
    assert.equal(ended, 1, "onEnd ran on cleanup");
});

// ---------------- DOM wiring ----------------

// Builds the indicator wrapper directly with a spy model (the full registry path is
// covered by the view tests); fires synthetic touches to drive a pull.
function wired(properties = { onRefreshActionID: "refreshX" }) {
    installDom();
    const scrollNode = makeElement("div");
    scrollNode.className = "aui-scroll"; // scrollTop is undefined in the stub => treated as "at top"
    const begun = [];
    const ctx = { model: { beginRefresh: (id, actionID, onEnd) => begun.push({ id, actionID, onEnd }) } };
    const wrapper = wrapWithPullToRefresh(scrollNode, { id: 7 }, properties, ctx);
    return { scrollNode, wrapper, begun };
}

test("no onRefreshActionID returns the node unchanged (no wrapper)", () => {
    installDom();
    const node = makeElement("div");
    assert.equal(wrapWithPullToRefresh(node, { id: 7 }, {}, { model: {} }), node);
});

test("the wrapper holds an indicator above the scroll node", () => {
    const { scrollNode, wrapper } = wired();
    assert.equal(wrapper.className, "aui-refresh");
    const [spinner, content] = wrapper.children;
    assert.equal(spinner.className, "aui-refresh-spinner");
    assert.equal(content, scrollNode, "scroll node sits below the indicator");
    assert.equal(spinner.children[0].className, "aui-refresh-glyph");
});

test("a full pull past the threshold begins a refresh; onEnd retracts the indicator", () => {
    const { scrollNode, wrapper, begun } = wired();
    const spinner = wrapper.children[0];

    scrollNode.fire("touchstart", { touches: [{ clientY: 100 }] });
    scrollNode.fire("touchmove", { touches: [{ clientY: 180 }], cancelable: true, preventDefault() {} });
    assert.ok(wrapper.classList.contains("is-armed"), "80px past the top arms it");
    assert.equal(spinner.style.height, `${resistedPull(80)}px`, "indicator follows the pull");

    scrollNode.fire("touchend", { changedTouches: [{ clientY: 180 }] });
    assert.deepEqual(begun.map((b) => ({ id: b.id, actionID: b.actionID })), [{ id: 7, actionID: "refreshX" }]);
    assert.ok(wrapper.classList.contains("is-refreshing"));
    assert.equal(spinner.style.height, `${INDICATOR_HEIGHT}px`, "held while refreshing");

    begun[0].onEnd(); // the model signals completion
    assert.equal(wrapper.classList.contains("is-refreshing"), false);
    assert.equal(spinner.style.height, "0px", "retracted");
});

test("a short pull snaps back without refreshing", () => {
    const { scrollNode, wrapper, begun } = wired();
    const spinner = wrapper.children[0];

    scrollNode.fire("touchstart", { touches: [{ clientY: 100 }] });
    scrollNode.fire("touchmove", { touches: [{ clientY: 130 }], cancelable: true, preventDefault() {} }); // 30px < 64
    assert.equal(wrapper.classList.contains("is-armed"), false);
    scrollNode.fire("touchend", { changedTouches: [{ clientY: 130 }] });

    assert.equal(begun.length, 0, "no refresh fired");
    assert.equal(spinner.style.height, "0px", "snapped back");
});

test("a pull that starts below the top is a scroll, not a refresh", () => {
    const { scrollNode, wrapper, begun } = wired();
    scrollNode.scrollTop = 50; // not at the top
    scrollNode.fire("touchstart", { touches: [{ clientY: 100 }] });
    scrollNode.fire("touchmove", { touches: [{ clientY: 200 }], cancelable: true, preventDefault() {} });
    scrollNode.fire("touchend", { changedTouches: [{ clientY: 200 }] });
    assert.equal(begun.length, 0, "scrolling from mid-list never refreshes");
    assert.equal(wrapper.classList.contains("is-armed"), false);
});
