#pragma once

#include <stddef.h>
#include <stdint.h>

struct evbuf {
    int fd;

    char *client_buffer;
    size_t bufsz, buflen;
};

int64_t evbuf_write(struct evbuf *buf, const void *data, size_t len);
