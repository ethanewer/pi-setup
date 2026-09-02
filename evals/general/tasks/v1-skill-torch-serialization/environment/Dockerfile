FROM bench-base:python-3.12

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