#include "CLinkedAddOns.h"
#include <stddef.h>

// Defined by the package that links the add-ons into libActionUI.so (ActionUIAdwaita/Library). A weak reference,
// because ActionUI cannot depend on what depends on it: it is NULL in any other program.
extern void ActionUILinkedAddOns_register(void) __attribute__((weak));

void actionUIRegisterLinkedAddOns(void) {
    if (ActionUILinkedAddOns_register != NULL) {
        ActionUILinkedAddOns_register();
    }
}
