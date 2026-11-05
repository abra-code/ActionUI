// ActionUIAdwaita/Library/Sources/ActionUILibrary/LinkedAddOns.swift
/*
 The add-ons in libActionUI.so. ActionUIModel calls this once, on the main thread, before the first document loads
 (actionUIRegisterLinkedAddOns), because a program in another language has no register() to call. A load-time
 constructor cannot do it: libdispatch binds the main queue to the thread that first uses it, and a library may be
 loaded on any thread. A new add-on is a dependency in Package.swift and a line here.
*/

import ActionUICachedImage
import ActionUIDiff
import ActionUIHostSurface
import ActionUIRichText

@c public func ActionUILinkedAddOns_register() {
    MainActor.assumeIsolated {
        ActionUIRichText.register()
        ActionUICachedImage.register()
        ActionUIDiff.register()
        ActionUIHostSurface.register()
    }
}
