#include "CLinkedAddOns.h"
#include <stddef.h>

// Defined by what links the add-ons into the same program or library (on Linux, the package that builds
// libActionUI.so). ActionUI cannot depend on what depends on it, so where no add-ons are linked the reference must
// resolve to a function that does nothing. COFF has no weak undefined reference as ELF has; the linker's alternate
// name gives the same result: where no object defines ActionUILinkedAddOns_register, the linker uses
// actionUINoLinkedAddOns.
void ActionUILinkedAddOns_register(void);

#if defined(_WIN32)
// External, never static: the alternate name must find it at link time.
void actionUINoLinkedAddOns(void);
void actionUINoLinkedAddOns(void) {
}
#pragma comment(linker, "/alternatename:ActionUILinkedAddOns_register=actionUINoLinkedAddOns")

void actionUIRegisterLinkedAddOns(void) {
    ActionUILinkedAddOns_register();
}
#else
// Only for building the module elsewhere (a type check on the Mac): a weak reference, as on Linux.
#pragma weak ActionUILinkedAddOns_register

void actionUIRegisterLinkedAddOns(void) {
    if (ActionUILinkedAddOns_register != NULL) {
        ActionUILinkedAddOns_register();
    }
}
#endif
