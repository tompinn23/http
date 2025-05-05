#include "ev.h"

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int xwrite(int fd, const void *buf, size_t len) {
    size_t left = len;
    int total = 0;
    int rc;
    const void *p = buf;

again:
    rc = write(fd, p, left);
    if(rc < 0) {
        if(errno == EINTR) {
            goto again;
        }
        return -1;
    }
    total += rc;
    if(rc < left) {
        left -= rc;
    }
    if(left == 0) {
        return total;
    }
    goto again;
}

int64_t evbuf_write(struct evbuf *ev, const void *data, size_t len) {
    if(ev->buflen > 0) {
        xwrite(ev->fd, );
    }
}
