#ifndef ACTIONUI_CLINUXSOCKET_H
#define ACTIONUI_CLINUXSOCKET_H

#include <sys/socket.h>

// accept4(2), which accepts a connection with its descriptor already close-on-exec and
// non-blocking. glibc exports it but declares it only for _GNU_SOURCE, which Swift's Glibc module
// is built without. With _GNU_SOURCE (__USE_GNU) glibc's own declaration is there instead.
#ifndef __USE_GNU
extern int accept4(int fd, struct sockaddr *address, socklen_t *length, int flags);
#endif

#endif
