#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import importlib.util
spec = importlib.util.spec_from_file_location("rmod", "/app/render.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
render = mod.render_html
cases = [
    "<script>alert(1)</script>",
    '"><img src=x onerror=alert(1)>',
    "<b>bold</b>",
    "a & b",
    "<svg onload=alert(1)>",
]
for inp in cases:
    out = render(inp)
    assert out.startswith("<div>") and out.endswith("</div>"), out
    inner = out[len("<div>"):-len("</div>")]
    assert "<" not in inner and ">" not in inner, out
assert "&amp;" in render("a & b"), render("a & b")
assert "&quot;" in render('"hello"'), render('"hello"')
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt