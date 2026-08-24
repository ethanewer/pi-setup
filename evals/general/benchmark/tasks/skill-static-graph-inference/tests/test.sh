#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/traced.pt ] && [ -f /app/out.txt ]; then
  if python3 - <<'PY'
import torch, importlib.util

x = torch.tensor([1.5, -2.0])

loaded = torch.jit.load('/app/traced.pt')
if not isinstance(loaded, torch.jit.ScriptModule):
    raise SystemExit(type(loaded))

spec = importlib.util.spec_from_file_location('m', '/app/model.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
ref = m.Net()
ref.load_state_dict(torch.load('/app/policy.pt', weights_only=False))
ref.eval()
expected = ref(x)

traced_out = loaded(x)
if not torch.allclose(traced_out, expected, atol=1e-5):
    raise SystemExit((traced_out, expected))

lines = [ln.strip() for ln in open('/app/out.txt') if ln.strip()]
if len(lines) != 2:
    raise SystemExit(lines)
got = torch.tensor([float(lines[0]), float(lines[1])])
if not torch.allclose(got, expected, atol=1e-5):
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt