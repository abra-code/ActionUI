// CWinUI.h - the C API the WinUI renderer imports as the module CWinUI: ActionUI's WinUI shim
// (ActionUIWinUIShim.dll, built from ActionUIWinUI/Shim by Scripts/ci-windows.py) and
// libdispatch's main-queue hooks.

#ifndef ACTIONUI_CWINUI_H
#define ACTIONUI_CWINUI_H

#include "../Shim/include/ActionUIWinUIShim.h"

// libdispatch's main-queue hooks, the ones CoreFoundation's run loop uses on Windows: a Win32
// event (auto-reset) that is signaled when the main queue has work, and a call that runs that
// work. libdispatch exports them but declares them only in its private headers.
extern void *_dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);

#endif /* ACTIONUI_CWINUI_H */
