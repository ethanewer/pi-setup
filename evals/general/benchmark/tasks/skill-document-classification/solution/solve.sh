#!/bin/bash
set -euo pipefail
cat > /app/classify.py <<'PY'
import os, re, csv

def tokens(text):
    return set(re.split(r'[^a-z0-9]+', text.lower()))

# Learn label -> token set for each training doc
train = {}
for row in csv.reader(open('/app/train.csv')):
    fname, label = row[0].strip(), row[1].strip()
    text = open(os.path.join('/app/train', fname)).read()
    train[label] = tokens(text)

order = ['sports', 'finance', 'tech']
with open('/app/predictions.txt', 'w') as out:
    for name in sorted(os.listdir('/app/test')):
        toks = tokens(open(os.path.join('/app/test', name)).read())
        best = None
        best_score = -1
        for label in order:  # tie-break: sports < finance < tech keeps stability
            score = len(toks & train[label])
            if score > best_score:
                best_score = score
                best = label
        out.write(f"{name} {best}\n")
PY
python3 /app/classify.py