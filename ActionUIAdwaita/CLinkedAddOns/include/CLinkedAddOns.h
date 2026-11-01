#ifndef ACTIONUI_CLINKEDADDONS_H
#define ACTIONUI_CLINKEDADDONS_H

// Registers the add-ons linked into the same library, for programs that cannot call an add-on's register():
// Python, Node.js, Rust and C load libActionUI.so and only call its C functions. Does nothing where no add-ons are
// linked: a Swift program registers the ones it links.
__attribute__((visibility("hidden"))) void actionUIRegisterLinkedAddOns(void);

#endif
