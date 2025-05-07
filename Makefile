MAKEFLAGS += -rR
.SUFFIXES:

exe := http

CC := gcc

CFLAGS := -ggdb3 -D_POSIX_C_SOURCE=200809L -D_GNU_SOURCE
LDFLAGS :=
O := .o

OBJS := main.o parse.tab.o list.o

deps := $(patsubst %.o, %.d, $(addprefix $O/, $(OBJS)))


.PHONY: all clean distclean
all: $(exe)

$(exe): $(addprefix $O/, $(OBJS))
	@echo "LD   $@"
	$(CC) $^ $(LDFLAGS) -o $@

parse.tab.c: parse.y
	@echo "YACC $@"
	@yacc $< -o $@


clean:
	rm -f $(addprefix $O/, $(OBJS))
	rm -f $(exe)

distclean: clean
	rm -f $(deps)

$O/%.o: %.c
	@[ -d $(dir $@) ] || mkdir -p $(dir $@)
	@echo "CC   $@"
	@$(CC) $(CFLAGS) -MMD -c $< -o $@

-include $(deps)
