// Tests for the textContentType -> web input-hint mapping (src/Helpers/
// TextContentType.js) and the TextField / SecureField validation around it.
// The helper drives autofill (HTML autocomplete) and the soft keyboard (inputmode)
// from Apple's UITextContentType raw value; these pin the table and the
// pass-through / restriction rules the two fields apply.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger, makeElement } from "./dom-stub.mjs";
import { applyTextContentType, AUTOCOMPLETE, INPUTMODE } from "../src/Helpers/TextContentType.js";

let getConstruction;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
});

const validate = (type, props) => getConstruction(type).validateProperties(props, makeLogger());

test("applyTextContentType sets autocomplete + inputmode for a keyboard-bearing type", () => {
    const input = makeElement("input");
    applyTextContentType(input, "emailAddress");
    assert.equal(input.autocomplete, "email");
    assert.equal(input.inputMode, "email");
});

test("applyTextContentType maps tel and url keyboards", () => {
    const tel = makeElement("input");
    applyTextContentType(tel, "telephoneNumber");
    assert.equal(tel.autocomplete, "tel");
    assert.equal(tel.inputMode, "tel");

    const url = makeElement("input");
    applyTextContentType(url, "url");
    assert.equal(url.autocomplete, "url");
    assert.equal(url.inputMode, "url");
});

test("a type with autofill but no unambiguous keyboard sets autocomplete only", () => {
    const input = makeElement("input");
    applyTextContentType(input, "givenName");
    assert.equal(input.autocomplete, "given-name");
    assert.equal(input.inputMode, undefined, "no inputmode override for a name field");
});

test("an unknown or non-string content type is a no-op (Apple pass-through)", () => {
    const unknown = makeElement("input");
    applyTextContentType(unknown, "notARealType");
    assert.equal(unknown.autocomplete, undefined);
    assert.equal(unknown.inputMode, undefined);

    const nonString = makeElement("input");
    applyTextContentType(nonString, 42);
    assert.equal(nonString.autocomplete, undefined);
});

test("the secure subset maps identically in the shared table", () => {
    // SecureField relies on these three keys existing with these values.
    assert.equal(AUTOCOMPLETE.password, "current-password");
    assert.equal(AUTOCOMPLETE.newPassword, "new-password");
    assert.equal(AUTOCOMPLETE.oneTimeCode, "one-time-code");
    // oneTimeCode is numeric; the other two keep the default keyboard.
    assert.equal(INPUTMODE.oneTimeCode, "numeric");
    assert.equal(INPUTMODE.password, undefined);
});

test("TextField validation: any string passes, a non-string is dropped with a warning", () => {
    // Apple only type-checks textContentType, so an unknown string is kept (it is a
    // harmless no-op when mapped).
    assert.equal(validate("TextField", { textContentType: "emailAddress" }).textContentType, "emailAddress");
    assert.equal(validate("TextField", { textContentType: "somethingNew" }).textContentType, "somethingNew");

    const logger = makeLogger();
    const out = getConstruction("TextField").validateProperties({ textContentType: 5 }, logger);
    assert.equal(out.textContentType, undefined);
    assert.ok(logger.warned("textContentType must be a String"));
});

test("SecureField validation: only the masked set is allowed", () => {
    assert.equal(validate("SecureField", { textContentType: "newPassword" }).textContentType, "newPassword");

    const logger = makeLogger();
    // A general (non-secure) type is dropped even though it is a valid TextField type.
    const out = getConstruction("SecureField").validateProperties({ textContentType: "emailAddress" }, logger);
    assert.equal(out.textContentType, undefined);
    assert.ok(logger.warned("textContentType must be"));
});
