#!/bin/bash
# Verifier for item-016-hard: recompute authoritative values, compare to report.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json
from tokenizers import Tokenizer

def norm(s): return s.strip()

rows = [json.loads(l) for l in open('/app/data/data.jsonl', encoding='utf-8')]
seen = {}
for r in rows:
    key = norm(r['title'])
    if key not in seen:
        seen[key] = r
en = sorted([r for r in seen.values() if r['lang'] == 'en'], key=lambda r: r['id'])
def chunk(r): return norm(r['title']) + '\n' + norm(r['body'])

q = Tokenizer.from_file('/app/models/qwen/tokenizer.json')
d = Tokenizer.from_file('/app/models/deepseek/tokenizer.json')
def cnt(s): return (len(q.encode(s, add_special_tokens=False).ids),
                    len(d.encode(s, add_special_tokens=False).ids))

total_corpus = '\n'.join(chunk(r) for r in en)
exp_total = cnt(total_corpus)
exp_chars = len(total_corpus)
exp_rows = len(en)
cats = ['scientific', 'tech', 'world']
exp_cats = {}
for cat in cats:
    crows = [r for r in en if r['category'] == cat]
    exp_cats[cat] = cnt('\n'.join(chunk(r) for r in crows))

try:
    rep = json.load(open('/app/report/token_accountant.json'))
except Exception:
    rep = {}

points = 0.0
c = rep.get('counts') or {}

def cell_exact(cat, key, expval):
    try:
        return int(c[cat][key]) == int(expval)
    except Exception:
        return False

# core row accounting
if isinstance(rep.get('kept_rows'), int) and rep['kept_rows'] == exp_rows:
    points += 0.2
if isinstance(rep.get('total_corpus_chars'), int) and rep['total_corpus_chars'] == exp_chars:
    points += 0.1

# per category qwen/deepseek (6 checks) and total (2 checks): 1.2 max -> capped to 0.6
acc = 0.0
checks = []
for cat in cats:
    checks.append(cell_exact(cat, 'qwen2_5', exp_cats[cat][0]))
    checks.append(cell_exact(cat, 'deepseek', exp_cats[cat][1]))
checks.append(cell_exact('total', 'qwen2_5', exp_total[0]))
checks.append(cell_exact('total', 'deepseek', exp_total[1]))
for ok in checks:
    if ok: acc += 1
points += 0.6 * (acc / len(checks))

# efficiency flags: total fewest == deepseek, reproducible true
if rep.get('counts', {}).get('total', {}).get('fewest') == 'deepseek':
    points += 0.05
if rep.get('reproducible') is True:
    points += 0.05

print(f"{min(points, 1.0):.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt