FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

# numpy (required by the Triton interpreter) and CPU-only PyTorch.
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        numpy
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        torch --index-url https://download.pytorch.org/whl/cpu

# Pinned Triton: CPU *interpreter* mode (TRITON_INTERPRET=1) runs @triton.jit
# kernels with no GPU device.
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        triton==3.5.0

# Sanity-check the toolchain on this CPU-only image.
RUN python3 -c "import torch, triton; assert not torch.cuda.is_available(); print('torch', torch.__version__, 'triton', triton.__version__)"
