#include "stdlib.h"
#include <stdio.h>
#include <limits.h>
#include <errno.h>
#include <string.h>

#define OPTPARSE_IMPLEMENTATION
#include "optparse.h"

static int strtoi(const char *s, char **endptr, int base) {
    long x = strtol(s, endptr, base);
#if INT_MAX == LONG_MAX && INT_MIN == LONG_MIN
    return (int)x;
#else
    if(x > INT_MAX) {
        errno = ERANGE;
        return INT_MAX;
    }
    if(x < INT_MIN) {
        return INT_MIN;
    }
    return (int)x;
#endif
}

static void help(FILE *strm) {
    fprintf(strm, "http v0.1 a small http/1.1 server\n");
    fprintf(strm, "usage: http [options]\n");

    fprintf(strm, "options:\n");
    fputs("\t-h, --help     print this help message\n", strm);
    fputs("\t-w, --prefork  number of workers to initialize with\n", strm);
    fputs("\t-c, --config   specify config file\n", strm);

}

int parse_config(const char *);

int main(int argc, char **argv) {
    struct optparse_long longopts[] = {
        {"prefork", 'w', OPTPARSE_REQUIRED},
        {"help", 'h', OPTPARSE_NONE},
        {"config", 'c', OPTPARSE_REQUIRED},
        {0}
    };

    int prefork = 0;
    char *config;


    char *arg;
    int opt;
    struct optparse options;
    optparse_init(&options, argv);

    while((opt = optparse_long(&options, longopts, NULL)) != -1) {
        switch(opt) {
            case 'h':
                help(stdout);
                exit(EXIT_SUCCESS);
                break;
            case 'w':
                prefork = strtoi(options.optarg, NULL, 10);
                if(prefork < 0) {
                    fprintf(stderr, "no. of workers to prefork cannot be less than 0\n");
                    exit(EXIT_FAILURE);
                }
                break;
            case 'c':
                config = strdup(options.optarg);
                if(config == NULL) {
                    exit(EXIT_FAILURE);
                }
            case '?':
                fprintf(stderr, "%s: %s\n", argv[0], options.errmsg);
                exit(EXIT_FAILURE);
        }
    }
    if(config != NULL) {
        if(parse_config(config) < 0) {
            printf("parse failed for http.conf\n");
        }
    }
}
