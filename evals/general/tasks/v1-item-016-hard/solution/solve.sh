#!/bin/bash
set -uo pipefail
mkdir -p /app/report

python3 - <<'PY'
import json
from tokenizers import Tokenizer

def norm(s): return s.strip()

rows = [json.loads(l) for l in open('/app/data/data.jsonl', encoding='utf-8')]

# normalize + dedup by exact normalized title, keep lowest id
seen = {}
for r in rows:
    key = norm(r['title'])
    if key not in seen:
        seen[key] = r
uniq = list(seen.values())
en = sorted([r for r in uniq if r['lang'] == 'en'], key=lambda r: r['id'])

def chunk(r): return norm(r['title']) + '\n' + norm(r['body'])

q = Tokenizer.from_file('/app/models/qwen/tokenizer.json')
d = Tokenizer.from_file('/app/models/deepseek/tokenizer.json')

def cnt(s): return (len(q.encode(s, add_special_tokens=False).ids),
                    len(d.encode(s, add_special_tokens=False).ids))

total_corpus = '\n'.join(chunk(r) for r in en)
tot = cnt(total_corpus)

counts = {}
for cat in ['scientific', 'tech', 'world']:
    crows = sorted([r for r in en if r['category'] == cat], key=lambda r: r['id'])
    corpus = '\n'.join(chunk(r) for r in crows)
    qc, dc = cnt(corpus)
    counts[cat] = {
        "qwen2_5": qc, "deepseek": dc,
        "fewest": "deepseek" if dc < qc else ("qwen2_5" if qc < dc else "tie")
    }
counts['total'] = {
    "qwen2_5": tot[0], "deepseek": tot[1],
    "fewest": "deepseek" if tot[1] < tot[0] else ("qwen2_5" if tot[0] < tot[1] else "tie")
}

report = {
    "scope": "normalize; dedup-by-title(keep lowest id); lang==en; id asc; newline-joined",
    "pins": {
        "qwen": "Qwen/Qwen2.5-0.5B -pinned-snapshot",
        "deepseek": "deepseek-ai/DeepSeek-V3 -pinned-snapshot"
    },
    "kept_rows": len(en),
    "kept_by_category": {c: len([r for r in en if r['category'] == c]) for c in ['scientific', 'tech', 'world']},
    "counts": counts,
    "total_corpus_chars": len(total_corpus),
    "reproducible": True
}
with open('/app/report/token_accountant.json', 'w') as f:
    json.dump(report, f, indent=2)
print(json.dumps(report, indent=2))
PY
exit 0