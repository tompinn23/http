#include "list.h"

void list_init(struct list *list) {
	list->prev = list;
	list->next = list;
}

void list_insert(struct list *list, struct list *elm) {
	elm->prev = list;
	elm->next = list->next;
	list->next = elm;
	elm->next->prev = elm;
}

void list_remove(struct list *elm) {
	elm->prev->next = elm->next;
	elm->next->prev = elm->prev;
	elm->next = NULL;
	elm->prev = NULL;
}

int list_length(const struct list *list) {
	struct list *e;
	int count;
	count = 0;
	e = list->next;
	while (e != list) {
		e = e->next;
		count++;
	}
	return count;
}

int list_empty(const struct list *list) {
	return list->next == list;
}

void list_insert_list(struct list *list, struct list *other) {
	if (list_empty(other))
		return;
	other->next->prev = list;
	other->prev->next = list->next;
	list->next->prev = other->prev;
	list->next = other->next;
}
