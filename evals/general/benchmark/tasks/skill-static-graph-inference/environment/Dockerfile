FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

COPY files/model.py /app/model.py

RUN python3 - <<'PY'
import torch
import importlib.util
spec = importlib.util.spec_from_file_location('m', '/app/model.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
torch.manual_seed(123)
net = m.Net()
torch.save(net.state_dict(), '/app/policy.pt')
PY