#include "ev.h"

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

#define EVBUF_CAP 8192

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

int xread(int fd, void *buf, size_t len) {
    size_t amt = 0;
    int rc;

again:
    rc = read(fd, buf + amt, len - amt);
    if(rc < 0) {
        if(errno == EINTR) {
            goto again;
        }
        return -1;
    }
    amt += rc;
    if(amt < len) {
        goto again;
    }
    return amt;
}


static int evbuf_ensure(struct evbuf *ev, size_t len) {
    if(ev->bufstart + len < ev->bufsz) { return 1; }
    if(ev->bufsz >= EVBUF_CAP) {
        return 0;
    }
    size_t newlen = ev->bufsz * 2 >= EVBUF_CAP ? EVBUF_CAP : ev->bufsz * 2;
    void *new = realloc(ev->client_buffer, newlen);
    if(!new) {
        return 0;
    }
    ev->bufsz = newlen;
    ev->client_buffer = new;
    return 1;
}

int64_t evbuf_write(struct evbuf *ev, const void *data, size_t len) {
    int rc;
    if(ev->buflen > 0) {
        rc = xwrite(ev->fd, ev->client_buffer + ev->bufstart, ev->buflen);
        if(rc < 0) {
            return rc;
        }
        if(rc < ev->buflen) {
            ev->buflen -= rc;
        }
        if(ev->buflen == 0) {
            ev->bufstart = 0;
        } else {
            ev->bufstart += rc;
        }
    } else if(data != NULL && len > 0) {
        rc = xwrite(ev->fd, data, len);
        if(rc < 0) {
            return rc;
        }
        if(rc < len) {
            if(!evbuf_ensure(ev, len)) {
                return -1;
            }
            memcpy(ev->client_buffer + ev->bufstart, data + rc, len - rc);
        }
        return rc;
    } else {
        return 0;
    }
    return -1;
}

int64_t evbuf_read(struct evbuf *ev, void *data, size_t len) {
    return xread(ev->fd, data, len);
}
