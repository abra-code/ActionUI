// Tests for VideoPlayer (src/Views/VideoPlayer.js): the trust policy decides which addresses it
// plays. Less-trusted content plays only web addresses (a relative one resolves against the page);
// the host's own content plays any address the browser does.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let getConstruction;
let HOST_ORIGIN;

const remote = { source: "remote", url: "https://other.example/panel.json", trust: "lessTrusted" };

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
    ({ HOST_ORIGIN } = await import("../src/Common/TrustPolicy.js"));
});

const build = (url, origin, logger = makeLogger()) =>
    getConstruction("VideoPlayer").buildView({ type: "VideoPlayer", id: 0, properties: { url } }, { url }, { logger, origin });

// The text of `node` and its children (the DOM stub keeps each node's own text only).
const textOf = (node) => (node.textContent ?? "") + (node.children ?? []).map(textOf).join("");

const played = (node) => node.querySelector?.("video")?.src ?? node.children?.find?.((child) => child.tagName?.toLowerCase() === "video")?.src;

test("less-trusted content plays a web address, relative ones too", () => {
    for (const url of ["https://example.com/movie.mp4", "movie.mp4"]) {
        const node = build(url, remote);
        assert.ok(played(node), url);
    }
});

test("less-trusted content plays no other address", () => {
    for (const url of ["file:///etc/movie.mp4", "blob:https://example.com/1", "data:video/mp4;base64,AAAA"]) {
        const logger = makeLogger();
        const node = build(url, remote, logger);
        assert.equal(played(node), undefined, url);
        assert.ok(textOf(node).includes("Not allowed"), url);
        assert.ok(logger.warned(`VideoPlayer not playing '${url}': the trust policy refuses it`), url);
    }
});

test("the host's content plays any address", () => {
    assert.equal(played(build("data:video/mp4;base64,AAAA", HOST_ORIGIN)), "data:video/mp4;base64,AAAA");
});
