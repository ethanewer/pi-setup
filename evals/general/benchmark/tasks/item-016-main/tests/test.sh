#!/bin/bash
# Verifier for item-016-main: recomputes the counts and compares against the report.
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json
from tokenizers import Tokenizer

rows = [json.loads(line) for line in open('/app/data/data.jsonl', encoding='utf-8')]
filt = sorted([r for r in rows if r['category'] == 'scientific' and r['lang'] == 'en'],
              key=lambda r: r['id'])
corpus = '\n'.join(r['title'] + '\n' + r['body'] for r in filt)
q = Tokenizer.from_file('/app/models/qwen/tokenizer.json')
d = Tokenizer.from_file('/app/models/deepseek/tokenizer.json')
exp_q = len(q.encode(corpus, add_special_tokens=False).ids)
exp_d = len(d.encode(corpus, add_special_tokens=False).ids)
exp_rows = len(filt)
exp_chars = len(corpus)
exp_large = 'qwen2_5' if exp_q > exp_d else 'deepseek'

try:
    rep = json.load(open('/app/report/token_counts.json'))
except Exception:
    rep = {}

core = 0.0
if isinstance(rep.get('filtered_rows'), int) and rep['filtered_rows'] == exp_rows:
    core += 1.0/3.0
if isinstance(rep.get('qwen2_5_tokens'), int) and rep['qwen2_5_tokens'] == exp_q:
    core += 1.0/3.0
if isinstance(rep.get('deepseek_tokens'), int) and rep['deepseek_tokens'] == exp_d:
    core += 1.0/3.0

extra = 0.0
if rep.get('larger_tokenizer') == exp_large:
    extra += 0.5
if isinstance(rep.get('corpus_chars'), int) and rep['corpus_chars'] == exp_chars:
    extra += 0.5

reward = core * 0.8 + extra * 0.2
print(f"{reward:.2f}")
PY
)
if [ -z "$reward" ]; then reward="0.00"; fi
echo "$reward" > /logs/verifier/reward.txt