#ifndef ACTIONUI_WINUI_CLINKEDADDONS_H
#define ACTIONUI_WINUI_CLINKEDADDONS_H

// Registers the add-ons linked into the same program or library, for programs that cannot call an add-on's
// register(): Python, Node.js, Rust and C load ActionUI.dll and only call its C functions. Does nothing where no
// add-ons are linked: a Swift program registers the ones it links. The Windows counterpart of
// ActionUIAdwaita/CLinkedAddOns.
void actionUIRegisterLinkedAddOns(void);

#endif
