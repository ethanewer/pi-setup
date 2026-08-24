#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PY'
from tokenizers import Tokenizer
import sys
tok = Tokenizer.from_file('/app/tokenizer/tokenizer.json')
text = open('/app/text.txt').read()
expected = str(len(tok.encode(text).ids))
got = open('/app/answer.txt').read().strip()
if got == expected:
    print("PASS"); sys.exit(0)
print("FAIL got=%r exp=%r" % (got, expected)); sys.exit(1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt