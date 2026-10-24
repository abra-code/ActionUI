#ifndef ACTIONUI_CSOUP_H
#define ACTIONUI_CSOUP_H

// libsoup 3, for loading http and https URLs (AsyncImage). The oldest version ActionUI supports is
// GNOME 48's, 3.6; a call that needs a newer one compiles with a deprecation warning, as the
// version macros in CAdwaita.h make GTK's do.
#define SOUP_VERSION_MIN_REQUIRED SOUP_VERSION_3_6
#define SOUP_VERSION_MAX_ALLOWED SOUP_VERSION_3_6

#include <libsoup/soup.h>

#endif
