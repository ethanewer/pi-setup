// GPU trainer for saltern. Only ever compiled when USE_GPU=ON; this file is
// not part of the CPU-only build.
#include <cuda_runtime.h>
#include <cstdio>

int main() {
    int ndev = 0;
    cudaGetDeviceCount(&ndev);
    std::printf("saltern_gpu devices=%d\n", ndev);
    return 0;
}
