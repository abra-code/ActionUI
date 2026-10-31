// Add-ons/ActionUIRichText/Sources/RichTextView+RemoteImages.swift
//
// The "remoteImages" property, read the same way on every platform.

import RichText

extension RichTextView {
    // The policy a "remoteImages" property value gives. Fails closed: absent is "automatic", but a value
    // that is present and not one of the three names is "on-click" - whoever set the key meant to
    // restrict fetching, so a misspelling must not turn into fetching at once.
    static func effectiveRemoteImagesPolicy(_ value: Any?) -> RichTextRemoteImages {
        if let policy = remoteImagesPolicy(value) {
            return policy
        }
        return value == nil ? .automatic : .onClick
    }

    // The document spelling of RichTextRemoteImages, the same as the Chat element's "remoteImages";
    // nil for anything else.
    static func remoteImagesPolicy(_ value: Any?) -> RichTextRemoteImages? {
        switch value as? String {
        case "automatic": return .automatic
        case "on-click": return .onClick
        case "never": return .never
        default: return nil
        }
    }
}
