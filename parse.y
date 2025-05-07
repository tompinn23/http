%{
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <sys/time.h>
#include <errno.h>


#include "list.h"

static struct list files = LIST_INIT(files);
static struct file {
    struct list entry;
    FILE       *stream;
    char       *name;
    size_t      ungetpos;
    size_t      ungetsize;
    char       *ungetbuf;
    int         eof;
    int         lineno;
    int         errors;
} *file, *topfile;

struct file *pushfile(const char *, int);
int popfile(void);

int yyparse(void);
int yylex(void);
int yyerror(const char *, ...) __attribute((__format__ (printf, 1, 2)));
int		 kw_cmp(const void *, const void *);
int		 lookup(char *);
int		 igetc(void);
int		 lgetc(int);
void	 lungetc(int);
int		 findeol(void);

long long strtonum(const char *ptr, long long min, long long max, const char **err);
void err(int, const char *fmt, ...);

static struct list syms = LIST_INIT(syms);
struct sym {
    struct list entry;

    int used;
    int persist;
    char *nam;
    char *val;
};

int symset(const char *, const char *, int);
char *symget(const char *);

static int errors = 0;
static int loadcfg = 0;

typedef struct {
    union {
        int64_t        number;
        char          *string;
        struct timeval tv;
    } v;
    int lineno;
} YYSTYPE;

%}


%token INCLUDE PREFORK ERROR
%token <v.string> STRING
%token <v.number> NUMBER


%%

grammar :
        | grammar include '\n'
        | grammar '\n'
        | grammar main '\n'
        | grammar error '\n' { file->errors++; }
        ;

include : INCLUDE STRING {
            struct file *nfile;
            if((nfile = pushfile($2, 0)) == NULL) {
                yyerror("failed to include file '%s'", $2);
                free($2);
                YYERROR;
            }
            free($2);

            file = nfile;
            lungetc('\n');
        }
        ;

main : PREFORK NUMBER {
        if(loadcfg) break;
        if($2 <= 0) {
            yyerror("invalid number for prefork '%lld'", $2);
            YYERROR;
        }
        //TODO: assign
     }
     ;

%%

struct keywords {
    const char *kname;
    int kval;
};

int yyerror(const char *fmt, ...) {
    va_list ap;
    char *msg;

    file->errors++;
    va_start(ap, fmt);
    if(vasprintf(&msg, fmt, ap) == -1) {
        return 0;
    }
    va_end(ap);

    printf("%s:%d %s\n", file->name, yylval.lineno, msg);
    free(msg);
    return 0;
}

void err(int exitcode, const char *fmt, ...) {
    va_list va;
    va_start(va, fmt);
    vfprintf(stderr, fmt, va);
    va_end(va);
    exit(exitcode);
}

int kw_cmp(const void *k, const void *e) {
    return strcmp(k, ((const struct keywords *)e)->kname);
}

int lookup(char *s) {
    /* maintain sorted list */
    static const struct keywords keywords[] = {
        {"prefork", PREFORK},
    };

    const struct keywords *p;
    p = bsearch(s, keywords, sizeof(keywords)/sizeof(keywords[0]), sizeof(keywords[0]), kw_cmp);

    if(p) {
        return (p->kval);
    } else {
        return STRING;
    }
}

char *symget(const char *nam) {
    struct sym *sym;
    list_for_each(sym, &syms, entry) {
        if(strcmp(nam, sym->nam) == 0) {
            sym->used = 1;
            return sym->val;
        }
    }
    return NULL;
}

long long strtonum(const char *ptr, long long minval, long long maxval, const char **errstr) {
    char *endptr = NULL;
    errno = 0;

    if (errstr) *errstr = NULL;

    long long result = strtoll(ptr, &endptr, 0);

    if (ptr[0] == '\0' || *endptr != '\0') {
        if (errstr) *errstr = "invalid";
        return 0;
    }
    if ((result == LLONG_MIN || result == LLONG_MAX) && errno == ERANGE) {
        if (errstr) *errstr = "overflow";
        return 0;
    }
    if (result < minval) {
        if (errstr) *errstr = "too small";
        return 0;
    }
    if (result > maxval) {
        if (errstr) *errstr = "too large";
        return 0;
    }

    return result;
}


#define START_EXPAND	1
#define DONE_EXPAND	2

static int	expanding;

int igetc(void) {
	int	c;

	while (1) {
		if (file->ungetpos > 0)
			c = file->ungetbuf[--file->ungetpos];
		else
			c = getc(file->stream);

		if (c == START_EXPAND)
			expanding = 1;
		else if (c == DONE_EXPAND)
			expanding = 0;
		else
			break;
	}
	return (c);
}

int lgetc(int quotec) {
	int		c, next;

	if (quotec) {
		if ((c = igetc()) == EOF) {
			yyerror("reached end of file while parsing "
			    "quoted string");
			if (file == topfile || popfile() == EOF)
				return (EOF);
			return (quotec);
		}
		return (c);
	}

	while ((c = igetc()) == '\\') {
		next = igetc();
		if (next != '\n') {
			c = next;
			break;
		}
		yylval.lineno = file->lineno;
		file->lineno++;
	}

	if (c == EOF) {
		/*
		 * Fake EOL when hit EOF for the first time. This gets line
		 * count right if last line in included file is syntactically
		 * invalid and has no newline.
		 */
		if (file->eof == 0) {
			file->eof = 1;
			return ('\n');
		}
		while (c == EOF) {
			if (file == topfile || popfile() == EOF)
				return (EOF);
			c = igetc();
		}
	}
	return (c);
}

void lungetc(int c) {

	if (c == EOF)
		return;

	if (file->ungetpos >= file->ungetsize) {
		void *p = reallocarray(file->ungetbuf, file->ungetsize, 2);
		if (p == NULL)
			err(1, "%s", __func__);
		file->ungetbuf = p;
		file->ungetsize *= 2;
	}
	file->ungetbuf[file->ungetpos++] = c;
}

int findeol(void) {
	int	c;

	/* skip to either EOF or the first real EOL */
	while (1) {
		c = lgetc(0);
		if (c == '\n') {
			file->lineno++;
			break;
		}
		if (c == EOF)
			break;
	}
	return (ERROR);
}

int yylex(void) {
	char		 buf[8096];
	char		*p, *val;
	int		 quotec, next, c;
	int		 token;

top:
	p = buf;
	while ((c = lgetc(0)) == ' ' || c == '\t')
		; /* nothing */

	yylval.lineno = file->lineno;
	if (c == '#')
		while ((c = lgetc(0)) != '\n' && c != EOF)
			; /* nothing */
	if (c == '$' && !expanding) {
		while (1) {
			if ((c = lgetc(0)) == EOF)
				return (0);

			if (p + 1 >= buf + sizeof(buf) - 1) {
				yyerror("string too long");
				return (findeol());
			}
			if (isalnum(c) || c == '_') {
				*p++ = c;
				continue;
			}
			*p = '\0';
			lungetc(c);
			break;
		}
		val = symget(buf);
		if (val == NULL) {
			yyerror("macro '%s' not defined", buf);
			return (findeol());
		}
		p = val + strlen(val) - 1;
		lungetc(DONE_EXPAND);
		while (p >= val) {
			lungetc(*p);
			p--;
		}
		lungetc(START_EXPAND);
		goto top;
	}

	switch (c) {
	case '\'':
	case '"':
		quotec = c;
		while (1) {
			if ((c = lgetc(quotec)) == EOF)
				return (0);
			if (c == '\n') {
				file->lineno++;
				continue;
			} else if (c == '\\') {
				if ((next = lgetc(quotec)) == EOF)
					return (0);
				if (next == quotec || next == ' ' ||
				    next == '\t')
					c = next;
				else if (next == '\n') {
					file->lineno++;
					continue;
				} else
					lungetc(next);
			} else if (c == quotec) {
				*p = '\0';
				break;
			} else if (c == '\0') {
				yyerror("syntax error");
				return (findeol());
			}
			if (p + 1 >= buf + sizeof(buf) - 1) {
				yyerror("string too long");
				return (findeol());
			}
			*p++ = c;
		}
		yylval.v.string = strdup(buf);
		if (yylval.v.string == NULL)
			err(1, "%s", __func__);
		return (STRING);
	}

#define allowed_to_end_number(x) \
	(isspace(x) || x == ')' || x ==',' || x == '/' || x == '}' || x == '=')

	if (c == '-' || isdigit(c)) {
		do {
			*p++ = c;
			if ((size_t)(p-buf) >= sizeof(buf)) {
				yyerror("string too long");
				return (findeol());
			}
		} while ((c = lgetc(0)) != EOF && isdigit(c));
		lungetc(c);
		if (p == buf + 1 && buf[0] == '-')
			goto nodigits;
		if (c == EOF || allowed_to_end_number(c)) {
            const char *errstr = NULL;

			*p = '\0';
			yylval.v.number = strtonum(buf, LLONG_MIN, LLONG_MAX, &errstr);
			if (errstr) {
				yyerror("\"%s\" invalid number: %s",
				    buf, errstr);
				return (findeol());
			}
			return (NUMBER);
		} else {
nodigits:
			while (p > buf + 1)
				lungetc(*--p);
			c = *--p;
			if (c == '-')
				return (c);
		}
	}

#define allowed_in_string(x) \
	(isalnum(x) || (ispunct(x) && x != '(' && x != ')' && \
	x != '{' && x != '}' && x != '<' && x != '>' && \
	x != '!' && x != '=' && x != '#' && \
	x != ',' && x != ';' && x != '/'))

	if (isalnum(c) || c == ':' || c == '_' || c == '*') {
		do {
			*p++ = c;
			if ((size_t)(p-buf) >= sizeof(buf)) {
				yyerror("string too long");
				return (findeol());
			}
		} while ((c = lgetc(0)) != EOF && (allowed_in_string(c)));
		lungetc(c);
		*p = '\0';
		if ((token = lookup(buf)) == STRING)
			if ((yylval.v.string = strdup(buf)) == NULL)
				err(1, "%s", __func__);
		return (token);
	}
	if (c == '\n') {
		yylval.lineno = file->lineno;
		file->lineno++;
	}
	if (c == EOF)
		return (0);
	return (c);
}

struct file *pushfile(const char *name, int secret) {
    struct file *nfile;

    if((nfile = calloc(1, sizeof(*nfile))) == NULL) {
        return NULL;
    }
    if((nfile->name = strdup(name)) == NULL) {
        free(nfile);
        return NULL;
    }

    if((nfile->stream = fopen(nfile->name, "r")) == NULL) {
        free(nfile->name);
        free(nfile);
        return NULL;
    }

    nfile->lineno = list_empty(&files) ? 1 : 0;
    nfile->ungetsize = 16;
    nfile->ungetbuf = malloc(nfile->ungetsize);
    if(nfile->ungetbuf == NULL) {
        fclose(nfile->stream);
        free(nfile->name);
        free(nfile);
        return NULL;
    }

    list_insert(&files, &nfile->entry);
    return nfile;
}

int popfile() {
    struct file *prev;
    if((prev = container_of(file->entry.prev, prev, entry)) != NULL) {
        prev->errors += file->errors;
    }
    list_remove(&file->entry);
    fclose(file->stream);
    free(file->name);
    free(file->ungetbuf);
    free(file);
    if(!list_empty(&files)) {
        file = prev;
    } else {
        file = NULL;
    }
    return (file ? 0 : EOF);
}

int parse_config(const char *fname) {
//    struct sym *sym, *next;

    errors = 0;
    if((file = pushfile(fname, 0)) == NULL)
        return -1;

    topfile = file;
    yyparse();
    errors = file->errors;
    while(popfile() != EOF) {}

    return (errors ? -1 : 0);
}
