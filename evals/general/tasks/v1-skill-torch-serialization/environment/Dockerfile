FROM bench-base:python-3.12

# [environment] declares cpus = 2, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    NUMEXPR_NUM_THREADS=2

WORKDIR /app

# CPU-only PyTorch wheels (torch.load / torch.save sandbox).
RUN pip install --no-cache-dir torch>=2.2

# Deterministically generate the serialized state dict (task input).
RUN python3 - <<'EOF'
import torch

w = torch.arange(12, dtype=torch.float32).reshape(3, 4)
b = torch.tensor([2.0, 4.0, 6.0, 8.0], dtype=torch.float32)
state = {"w": w, "b": b}
torch.save(state, "/app/model.pt")
EOF