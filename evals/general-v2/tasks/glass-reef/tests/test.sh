#!/bin/bash
# Verifier for tasks/glass-reef. Executes the deliverable /app/clean.py on the
# visible case and on hidden adversarial inputs, canonicalizes the outputs, and
# requires every one to match its canonical expected fragment.
mkdir -p /logs/verifier
reward=0
if [ ! -f /app/clean.py ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# ---- deterministic canonicalizer (kept entirely inside the verifier) ----
cat > /tmp/canon.py <<'PYEOF'
import sys
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta',
        'param','source','track','wbr'}

class C(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
    def handle_starttag(self, tag, attrs):
        tag = tag.strip().lower()
        self.out.append('<'+tag)
        merged = {}
        for n, v in attrs:
            n = (n or '').strip().lower()
            if n not in merged:
                merged[n] = ''
            if v is not None:
                merged[n] = (merged[n] + ' ' + v).strip()
        for n in sorted(merged):
            val = merged[n].replace('&','&amp;').replace('"','&quot;')
            self.out.append(' '+n+'="'+val+'"')
        self.out.append('>')
    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
    def handle_endtag(self, tag):
        tag = tag.strip().lower()
        if tag not in VOID:
            self.out.append('</'+tag+'>')
    def handle_data(self, data):
        data = ' '.join(data.split())
        if data:
            self.out.append(data)
    def handle_comment(self, data):
        self.out.append('<!--'+' '.join((data or '').split())+'-->')
    def handle_decl(self, decl):
        pass
    def handle_pi(self, data):
        pass

def canon(s):
    c = C()
    c.feed(s)
    c.close()
    return ''.join(c.out)

sys.stdout.write(canon(open(sys.argv[1]).read()))
PYEOF

ok=1
checked=0

verify_case() {
  local name="$1" input="$2" expect_file="$3"
  local out=/tmp/out_clean.txt got=/tmp/got_canon.txt
  python3 /app/clean.py "$input" "$out" || { echo "[fail] $name: clean.py exited non-zero"; ok=0; return; }
  python3 /tmp/canon.py "$out" > "$got"
  if ! cmp -s "$got" "$expect_file"; then
    echo "[fail] $name: canonical mismatch"
    echo "  expected: $(cat "$expect_file")"
    echo "  got:      $(cat "$got")"
    ok=0
    return
  fi
  checked=$((checked+1))
  echo "[ok] $name"
}

# ---- visible case ----
vis_exp=/tmp/vis_exp.txt
python3 - /tests/expected.json "$vis_exp" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
open(sys.argv[2],'w').write(d['output'])
PY
verify_case "visible" /tests/inputs/visible.html "$vis_exp"

# ---- hidden cases ----
for inp in /tests/hidden/*.in; do
  [ -e "$inp" ] || continue
  name=$(basename "$inp" .in)
  exp="${inp%.in}.expected"
  if [ ! -f "$exp" ]; then
    echo "[fail] hidden-$name: missing expected file"; ok=0; continue
  fi
  verify_case "hidden-$name" "$inp" "$exp"
done

# at least the visible + 4 hidden cases must have run and matched
if [ "$ok" -eq 1 ] && [ "$checked" -ge 5 ]; then
  reward=1
fi
echo "checked=$checked reward=$reward"
echo "$reward" > /logs/verifier/reward.txt