// CSymbolResource.h - the Material Symbols icon resource compiled into ActionUI on Linux.
#ifndef ACTIONUI_C_SYMBOL_RESOURCE_H
#define ACTIONUI_C_SYMBOL_RESOURCE_H

#include <stdbool.h>

/// Registers the icon resource with GLib; false when the build had no generated resource
/// (Scripts/prepare-linux-symbols.sh was not run before swift build). Call it once.
bool actionui_symbol_resource_register(void);

#endif
