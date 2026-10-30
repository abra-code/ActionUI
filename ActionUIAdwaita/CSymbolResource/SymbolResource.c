/*
 The Material Symbols icons that stand in for SF Symbols on Linux, as one GResource in a section of
 its own (.gresource.actionui_symbols) of whatever links ActionUI: libActionUI.so, or a Swift
 program that links ActionUI statically. GLib reads it in place, and `gresource list` shows it.

 Scripts/prepare-linux-symbols.sh writes generated/symbols-resource.inc (glib-compile-resources
 --generate-source --manual-register) and touches this file, since a build that once found no such
 file does not look for it again otherwise. Without it ActionUI builds with no icons: the
 ActionUISymbolResourceCheck build plugin warns on every build, and MaterialSymbols logs an error.
*/

#include "CSymbolResource.h"

#if __has_include("generated/symbols-resource.inc")

#include "generated/symbols-resource.inc"

bool actionui_symbol_resource_register(void)
{
    actionui_symbols_register_resource();
    return true;
}

#else

bool actionui_symbol_resource_register(void)
{
    return false;
}

#endif
