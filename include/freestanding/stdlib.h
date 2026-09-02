/* Freestanding-wasm shim: only what vendor/md4c/md4c.c uses. Defined in src/libc.zig. */
#ifndef MD4ZIG_SHIM_STDLIB_H
#define MD4ZIG_SHIM_STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void *realloc(void *ptr, size_t size);
void free(void *ptr);
void qsort(void *base, size_t nmemb, size_t size,
           int (*compar)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
              int (*compar)(const void *, const void *));

#endif
