#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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