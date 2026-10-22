#ifndef ACTIONUI_CADWAITA_H
#define ACTIONUI_CADWAITA_H

// The oldest libraries ActionUI supports on Linux, those of GNOME 48: GTK 4.18, libadwaita 1.7 and
// GLib 2.84 (which also covers GIO: GApplication, GMenu, GFile). A call that needs a newer version
// compiles with the warning "is deprecated: Not available before X.Y", so it shows in the build
// even on a machine with newer libraries. Calls deprecated by the floor's versions warn too.
#define GLIB_VERSION_MIN_REQUIRED GLIB_VERSION_2_84
#define GLIB_VERSION_MAX_ALLOWED GLIB_VERSION_2_84
#define GDK_VERSION_MIN_REQUIRED GDK_VERSION_4_18
#define GDK_VERSION_MAX_ALLOWED GDK_VERSION_4_18
#define ADW_VERSION_MIN_REQUIRED ADW_VERSION_1_7
#define ADW_VERSION_MAX_ALLOWED ADW_VERSION_1_7

#include <adwaita.h>
#include <glib-unix.h>

// libdispatch's main-queue hooks, the ones CoreFoundation's run loop uses on Linux: a file
// descriptor that becomes readable when the main queue has work, and the call that runs it.
// libdispatch exports them but declares them only in its private headers.
extern int _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *msg);

#endif
