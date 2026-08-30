# The GPU enablement hook for the saltern trainer.
# saltern ships with USE_GPU=ON by default; this file makes that default
# honest: without an actual CUDA toolkit the configure step must fail loudly
# instead of silently degrading.
find_package(CUDAToolkit REQUIRED)
