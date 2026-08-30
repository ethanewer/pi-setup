#include "core.h"

long engine_value(long n) {
    if (n < 0) return 0L;
    return n * n;
}