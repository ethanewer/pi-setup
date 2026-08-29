#!/usr/bin/env bash
# vine-pier oracle: authors every deliverable from the shipped fixtures and
# does the real work, producing the report products by running them.
set -eu
DATA=/app/data

# 1) pure-C checkpoint + byte-pair vocabulary reader (source ships in solution/)
cp /solution/ckpt_reader.c /app/ckpt_reader.c
gcc -O2 -o /app/ckpt_reader /app/ckpt_reader.c
chmod +x /app/ckpt_reader

# 2. author + compile + run the three model programs and the report builder.
cp /solution/generate.py     /app/generate.py
chmod +x /app/generate.py
cp /solution/speculative.py  /app/speculative.py
chmod +x /app/speculative.py
cp /solution/retrieve.py     /app/retrieve.py
chmod +x /app/retrieve.py
cp /solution/report.py       /app/report.py
chmod +x /app/report.py

# 3) produce the visible report products by RUNNING the work.
python3 /app/generate.py --model /app/data/checkpoint.ckpt \
        --prompt 2,4 --out /app/greedy_out.json >/dev/null

# target sequence for the visible speculative pass: target-model greedy
# continuation of prefix [1,2] (computed deterministically with numpy).
python3 - <<'PY' > /tmp/spec_target.txt
import struct
import numpy as np
b = open("/app/data/checkpoint.ckpt", "rb").read()
o = 8
V = struct.unpack_from("<I", b, o)[0]; o += 4
nt = struct.unpack_from("<I", b, o)[0]; o += 4
mg = struct.unpack_from("<I", b, o)[0]; o += 4
struct.unpack_from("<I", b, o); o += 4
rl = struct.unpack_from("<I", b, o)[0]; o += 4
o += rl
ts = {}
for _ in range(nt):
    nl = struct.unpack_from("<I", b, o)[0]; o += 4
    nm = b[o:o + nl].decode("ascii"); o += nl
    struct.unpack_from("<B", b, o); o += 1
    nd = struct.unpack_from("<B", b, o)[0]; o += 1
    sh = struct.unpack_from("<%dI" % nd, b, o); o += 4 * nd
    n = int(np.prod(sh))
    ts[nm] = np.frombuffer(b[o:o + 4 * n], dtype="float32").reshape(sh).copy()
    o += 4 * n
W, B = ts["W"], ts["B"]
WB = W + B[None, None, :]
seq = [1, 2]
for _ in range(mg):
    seq.append(int(np.argmax(WB[seq[-2], seq[-1]])))
print(",".join(str(x) for x in seq[2:]))
PY
python3 /app/speculative.py --model /app/data/checkpoint.ckpt \
        --prefix "1,2" --target "$(cat /tmp/spec_target.txt)" --draft 3 \
        --out /app/spec_out.json >/dev/null

python3 /app/retrieve.py --model /app/data/checkpoint.ckpt \
        --docs "1,1,9;5,4;6,0;2,6,3;1,9,9" --query "2,4" \
        --out /app/ranks.json >/dev/null

python3 /app/report.py /app/data/checkpoint.ckpt

echo "vine-pier oracle: deliverables authored"
ls -l /app/ckpt_reader /app/ckpt_reader.c /app/generate.py /app/greedy_out.json \
       /app/speculative.py /app/spec_out.json /app/retrieve.py /app/ranks.json \
       /app/report.py /app/model.pkl /app/params.json