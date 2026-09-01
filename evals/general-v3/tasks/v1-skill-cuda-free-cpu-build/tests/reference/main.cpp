#include <cstdio>
#include "build_config.h"

int main() {
#ifdef USE_CUDA
    std::printf("BUILD_TARGET=gpu\n");
#else
    std::printf("BUILD_TARGET=cpu\n");
#endif
    return 0;
}