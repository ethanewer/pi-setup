FROM bench-base:python-3.12

WORKDIR /app

# Numeric stack (numpy/scipy/pandas via corporate CA 3.x proxy).
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        numpy scipy pandas

# CPU-only PyTorch from the official CPU wheel index.
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        torch --index-url https://download.pytorch.org/whl/cpu

# The pinned Triton version this task requires (see C-4e0123b6).
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        triton==3.4.0

# Committed fixtures: the causal-model state dict to reconstruct, plus the
# train / hold-out tables used by the tuning pipeline.
RUN mkdir -p /opt/causal/data
COPY files/state_dict.pt /opt/causal/data/state_dict.pt
COPY files/train.csv      /opt/causal/data/train.csv
COPY files/holdout.csv    /opt/causal/data/holdout.csv

# Sanity check the toolchain is usable (CPU build + interpreter-capable triton).
RUN python3 -c "import torch, numpy, triton, scipy, pandas; assert not torch.cuda.is_available(); print('torch', torch.__version__, 'triton', triton.__version__)"
RUN python3 -c "import os, torch; print('fixtures ok', [f for f in ('state_dict.pt','train.csv','holdout.csv')]); assert os.path.isfile('/opt/causal/data/state_dict.pt')"