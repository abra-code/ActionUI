// Tests for Link (src/Views/Link.js): linkDestination against the Link URL parity cases every
// renderer checks (FormatParity/link-url-cases.json at the repository root, recorded from
// Foundation on a Mac), and what the view builds for each destination.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { installDom, makeLogger } from "./dom-stub.mjs";

const cases = JSON.parse(readFileSync(new URL("../../FormatParity/link-url-cases.json", import.meta.url), "utf8"));

let linkDestination;
let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ linkDestination } = await import("../src/Views/Link.js"));
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const build = (properties, logger = makeLogger()) =>
    getConstruction("Link").buildView({ type: "Link", id: 1, properties }, properties, { logger });

test("every link url case gives its expected destination", () => {
    for (const item of cases.cases) {
        assert.equal(linkDestination(item.url), item.expected, JSON.stringify(item.url));
    }
});

test("a url with a scheme is an <a> opening in a new tab", () => {
    const node = build({ title: "Site", url: "https://example.com" });
    assert.equal(node.tagName.toLowerCase(), "a");
    assert.equal(node.href, "https://example.com");
    assert.equal(node.target, "_blank");
    assert.equal(node.textContent, "Site");
});

test("a url without a scheme is shown, focusable, and opens nothing", () => {
    const logger = makeLogger();
    const node = build({ url: "docs/page" }, logger);
    assert.equal(node.tagName.toLowerCase(), "a");
    assert.equal(node.href, undefined);
    assert.equal(node.getAttribute("role"), "link");
    assert.equal(node.tabIndex, 0);
    assert.equal(node.textContent, "Link");
    node.fire("click");
    node.fire("click");
    assert.equal(logger.warningCount(), 1, "logged once");
});

test("javascript and data urls open nothing", () => {
    for (const url of ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,<b>x</b>", "vbscript:x"]) {
        assert.equal(build({ url }).href, undefined, url);
    }
});

test("a refused or missing url renders nothing, untrimmed as on Apple", () => {
    for (const url of [undefined, "", " https://example.com", "http://a b/"]) {
        const logger = makeLogger();
        const node = build(url === undefined ? {} : { url }, logger);
        assert.equal(node.className, "aui-empty", String(url));
        assert.ok(logger.warned("Link missing valid URL"));
    }
});
