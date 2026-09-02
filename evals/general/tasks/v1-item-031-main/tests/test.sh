#!/bin/bash
# Verifier for item-031-main.
# Objective checks on a held-out image set + byte budget + self-containment.
mkdir -p /logs/verifier

BUDGET=2048
reward=0

if [ ! -f /app/predict.c ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# --- byte budget -------------------------------------------------------------
size=$(wc -c < /app/predict.c | tr -d ' ')
if [ "$size" -gt "$BUDGET" ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# --- self-containment (no shells/pythons/proc launching) ---------------------
if grep -aqE 'system\s*\(|popen|exec[lvpe]*\s*\(|fork\s*\(|python|/bin/sh|/bin/bash' /app/predict.c; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# --- compile -----------------------------------------------------------------
rm -f /tmp/predict
if ! gcc -O2 -o /tmp/predict /app/predict.c 2>/tmp/compile.err; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# --- held-out evaluation ------------------------------------------------------
matches=$(python3 - <<'EOF'
import json, random, subprocess
m = json.load(open("/app/model.json"))
w1 = m["w1"]; b1 = m["b1"]; w2 = m["w2"]; b2 = m["b2"]
H = len(b1)

def ref(img):
    x = [v / 255.0 for v in img]
    h = [max(sum(x[k] * w1[k][i] for k in range(784)) + b1[i], 0.0) for i in range(H)]
    y = [sum(h[i] * w2[i][j] for i in range(H)) + b2[j] for j in range(10)]
    return y.index(max(y))

N = 24
ok = 0
images = []
# two edge cases first: all zeros and all 255
images.append(bytes(784))
images.append(bytes([255]) * 784)
r = random.Random(7000)
for i in range(N - 2):
    images.append(bytes(r.randint(0, 255) for _ in range(784)))
for idx, img in enumerate(images):
    tmp = "/tmp/eval_%02d.raw" % idx
    open(tmp, "wb").write(img)
    exp = ref(img)
    got = subprocess.run(["/tmp/predict", tmp], capture_output=True, text=True, timeout=30)
    if got.returncode == 0 and got.stdout.strip() == str(exp):
        ok += 1
print(ok)
EOF
)

if [ "$matches" -ge 22 ]; then
  reward=1
elif [ "$matches" -ge 16 ]; then
  reward=0.5
else
  reward=0
fi

echo "$reward" > /logs/verifier/reward.txt