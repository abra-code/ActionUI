// Tests for how Image (src/Views/Image.js) scales a raster image, which follows SwiftUI: the
// image keeps its own size unless "resizable" is true; resizable alone stretches it to its box,
// and contentMode keeps its aspect ratio only when it is resizable.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const image = (properties) => {
    const construction = getConstruction("Image");
    const validated = construction.validateProperties(properties, makeLogger());
    const node = construction.buildView({ type: "Image", id: 0, properties: validated }, validated, { logger: makeLogger() });
    return node.children[0];
};

test("an image that is not resizable keeps its own size", () => {
    const img = image({ filePath: "a.png" });
    assert.equal(img.style.objectFit, undefined);
    assert.equal(img.style.width, undefined);
});

test("contentMode alone does not scale the image", () => {
    for (const contentMode of ["fit", "fill"]) {
        const img = image({ filePath: "a.png", contentMode });
        assert.equal(img.style.objectFit, undefined, contentMode);
        assert.equal(img.style.width, undefined, contentMode);
    }
});

test("resizable alone stretches the image to fill its box", () => {
    const img = image({ filePath: "a.png", resizable: true });
    assert.equal(img.style.objectFit, "fill");
    assert.equal(img.style.width, "100%");
    assert.equal(img.style.height, "100%");
});

test("resizable with a contentMode keeps the aspect ratio", () => {
    assert.equal(image({ filePath: "a.png", resizable: true, contentMode: "fit" }).style.objectFit, "contain");
    assert.equal(image({ filePath: "a.png", resizable: true, contentMode: "fill" }).style.objectFit, "cover");
});

test("resizable false with a contentMode keeps its own size", () => {
    const img = image({ filePath: "a.png", resizable: false, contentMode: "fit" });
    assert.equal(img.style.objectFit, undefined);
});
