#!/bin/bash
set -uo pipefail

mkdir -p /app/report
python3 - <<'PY'
import json
from tokenizers import Tokenizer

rows = [json.loads(line) for line in open('/app/data/data.jsonl', encoding='utf-8')]
filt = sorted([r for r in rows if r['category'] == 'scientific' and r['lang'] == 'en'],
              key=lambda r: r['id'])
chunks = [r['title'] + '\n' + r['body'] for r in filt]
corpus = '\n'.join(chunks)

q = Tokenizer.from_file('/app/models/qwen/tokenizer.json')
d = Tokenizer.from_file('/app/models/deepseek/tokenizer.json')

qcount = len(q.encode(corpus, add_special_tokens=False).ids)
dcount = len(d.encode(corpus, add_special_tokens=False).ids)

report = {
    "dataset": "news-sample-2024 (local snapshot)",
    "counting_scope": "category=scientific AND lang=en; sorted by id asc; joined with newline separators",
    "filtered_rows": len(filt),
    "corpus_chars": len(corpus),
    "revision_pins": {
        "qwen": "Qwen/Qwen2.5-0.5B (pinned snapshot)",
        "deepseek": "deepseek-ai/DeepSeek-V3 (pinned snapshot)"
    },
    "qwen2_5_tokens": qcount,
    "deepseek_tokens": dcount,
    "larger_tokenizer": "qwen2_5" if qcount > dcount else "deepseek"
}
with open('/app/report/token_counts.json', 'w') as f:
    json.dump(report, f, indent=2)
print(json.dumps(report, indent=2))
PY
exit 0