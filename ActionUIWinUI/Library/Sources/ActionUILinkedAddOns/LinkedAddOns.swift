// ActionUIWinUI/Library/Sources/ActionUILinkedAddOns/LinkedAddOns.swift
/*
 The add-ons in ActionUI.dll. ActionUIModel calls this once, on the main thread, before the first ActionUI JSON
 loads (actionUIRegisterLinkedAddOns), because a program in another language has no register() to call. A new
 add-on is a dependency in Package.swift and a line here, as in ActionUIAdwaita/Library. No add-on builds for
 Windows yet.
*/

@c public func ActionUILinkedAddOns_register() {
}
