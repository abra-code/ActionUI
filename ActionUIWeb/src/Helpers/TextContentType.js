// TextContentType.js - maps Apple's `textContentType` to the web's input hints.
//
// `textContentType` is a canonical Apple property on TextField / SecureField (the
// UITextContentType raw value; the full set is enumerated in ActionUI/Views/
// TextField.swift and Documentation/Schemas/TextField.md). It is ignored on macOS,
// but on a touch platform it drives two things the web also exposes natively:
//   * autofill - the HTML `autocomplete` token, so the browser/OS offers the right
//     saved value (the web analog of what UITextContentType does on iOS). This is
//     the mapping SecureField already shipped; the full table lives here so
//     TextField shares it.
//   * the soft keyboard - the HTML `inputmode`, so a phone shows the email / tel /
//     URL / numeric keypad for the content types whose keyboard is unambiguous
//     (the web analog of iOS picking a keyboard from the content type). Conservative
//     on purpose: only the content types with a single clearly-correct keyboard are
//     listed; everything else keeps the default text keyboard.
//
// Apple validates only that `textContentType` is a String and passes it straight to
// UITextContentType(rawValue:), so an unknown value is a harmless no-op. We mirror
// that: an unmapped value simply sets no hint (rather than warning or dropping).

// textContentType -> HTML autocomplete token (the WHATWG autofill field names).
export const AUTOCOMPLETE = {
    name: "name",
    namePrefix: "honorific-prefix",
    givenName: "given-name",
    middleName: "additional-name",
    familyName: "family-name",
    nameSuffix: "honorific-suffix",
    nickname: "nickname",
    jobTitle: "organization-title",
    organizationName: "organization",
    fullStreetAddress: "street-address",
    streetAddressLine1: "address-line1",
    streetAddressLine2: "address-line2",
    addressCity: "address-level2",
    addressState: "address-level1",
    sublocality: "address-level3",
    countryName: "country-name",
    postalCode: "postal-code",
    telephoneNumber: "tel",
    emailAddress: "email",
    url: "url",
    creditCardNumber: "cc-number",
    creditCardSecurityCode: "cc-csc",
    creditCardName: "cc-name",
    creditCardExpiration: "cc-exp",
    creditCardType: "cc-type",
    username: "username",
    password: "current-password",
    newPassword: "new-password",
    oneTimeCode: "one-time-code",
    birthdate: "bday",
    birthdateDay: "bday-day",
    birthdateMonth: "bday-month",
    birthdateYear: "bday-year",
};

// textContentType -> HTML inputmode (the soft keyboard). Only the content types
// with one clearly-correct keyboard; anything else keeps the default text keyboard.
export const INPUTMODE = {
    emailAddress: "email",
    telephoneNumber: "tel",
    url: "url",
    creditCardNumber: "numeric",
    creditCardSecurityCode: "numeric",
    oneTimeCode: "numeric",
};

// Applies the autofill + soft-keyboard hints for `contentType` to an <input>.
// A no-op for a non-string or an unmapped value (matching Apple's pass-through).
export function applyTextContentType(input, contentType) {
    if (typeof contentType !== "string") return;
    const autofill = AUTOCOMPLETE[contentType];
    if (autofill) input.autocomplete = autofill;
    const mode = INPUTMODE[contentType];
    if (mode) input.inputMode = mode;
}
