#pragma once

#include <stddef.h>

#define LIST_INIT(name) (struct list){ &name, &name }

#define typeof_member(T, m)	typeof(((T*)0)->m)

#define container_of(ptr, type, member)				\
	(__typeof__(type))((char *)(ptr) -				\
			     offsetof(__typeof__(*type), member))

#define container_of_const(ptr, type, member)				\
	_Generic(ptr,							\
		const typeof(*(ptr)) *: ((const type *)container_of(ptr, type, member)),\
		default: ((type *)container_of(ptr, type, member))	\
	)

#define list_for_each(pos, head, member)				\
	for (pos = container_of((head)->next, pos, member);	\
	     &pos->member != (head);					\
	     pos = container_of(pos->member.next, pos, member))

struct list {
    struct list *prev, *next;
};

void list_init(struct list *list);
void list_insert(struct list *list, struct list *elm);
void list_remove(struct list *elm);
int list_length(const struct list *list);
int list_empty(const struct list *list);
void list_insert_list(struct list *list, struct list *other);
