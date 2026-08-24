#!/bin/bash
set -euo pipefail
python3 - <<'PY'
from tokenizers import Tokenizer
tok=Tokenizer.from_file('/app/tokenizer/tokenizer.json')
text=open('/app/text.txt').read()
count=len(tok.encode(text).ids)
open('/app/answer.txt','w').write(str(count))
print('token count:', count)
PY
