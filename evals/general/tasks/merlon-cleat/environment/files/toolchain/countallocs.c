#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static unsigned long long ncall = 0;

static void *real_malloc(size_t n) {
    static void* (*f)(size_t);
    if (!f) f = (void*(*)(size_t))dlsym(RTLD_NEXT, "malloc");
    return f(n);
}
static void *real_calloc(size_t n, size_t s) {
    static void* (*f)(size_t, size_t);
    if (!f) f = (void*(*)(size_t, size_t))dlsym(RTLD_NEXT, "calloc");
    return f(n, s);
}
static void *real_realloc(void *p, size_t n) {
    static void* (*f)(void*, size_t);
    if (!f) f = (void*(*)(void*, size_t))dlsym(RTLD_NEXT, "realloc");
    return f(p, n);
}
static void *real_memalign(size_t a, size_t n) {
    static void* (*f)(size_t, size_t);
    if (!f) f = (void*(*)(size_t, size_t))dlsym(RTLD_NEXT, "memalign");
    return f(a, n);
}
static void *real_posix(size_t a, size_t n) {
    static void* (*f)(size_t, size_t);
    if (!f) f = (void*(*)(size_t, size_t))dlsym(RTLD_NEXT, "posix_memalign");
    return f(a, n);
}
static void real_free(void *p) {
    static void (*f)(void*);
    if (!f) f = (void(*)(void*))dlsym(RTLD_NEXT, "free");
    f(p);
}

void *malloc(size_t n) { ncall++; return real_malloc(n); }
void *calloc(size_t n, size_t s) { ncall++; return real_calloc(n, s); }
void *realloc(void *p, size_t n) { ncall++; return real_realloc(p, n); }
void *memalign(size_t a, size_t n) { ncall++; return real_memalign(a, n); }
int posix_memalign(void **p, size_t a, size_t n) {
    ncall++;
    int rc = real_posix(a, n) == 0 ? 0 : -1;
    (void)p;
    return rc;
}
void free(void *p) { real_free(p); }

static void report(void) {
    const char *path = getenv("ALLOCLOG");
    if (path && *path) {
        FILE *fh = fopen(path, "w");
        if (fh) {
            fprintf(fh, "ALLOCS=%llu\n", ncall);
            fclose(fh);
        }
    }
    fprintf(stderr, "SHIM_ALLOCS=%llu\n", ncall);
}

static void init(void) { atexit(report); }
__attribute__((constructor)) static void __shim_init(void) { init(); }