#!/bin/bash
# Verifier for item-031-hard. Objective checks on held-out images, budget,
# self-containment; reference computed from model_pytorch.json.
mkdir -p /logs/verifier

BUDGET=1536
reward=0

if [ ! -f /app/predict.c ] || [ ! -f /app/model_pytorch.json ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

size=$(wc -c < /app/predict.c | tr -d ' ')
if [ "$size" -gt "$BUDGET" ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

if grep -aqE 'system\s*\(|popen|exec[lvpe]*\s*\(|fork\s*\(|python|/bin/sh|/bin/bash' /app/predict.c; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

rm -f /tmp/predict
if ! gcc -O2 -o /tmp/predict /app/predict.c 2>/tmp/compile.err; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

matches=$(python3 - <<'EOF'
import json, random, subprocess
d = json.load(open("/app/model_pytorch.json"))
W1 = d["fc1.weight"]; B1 = d["fc1.bias"]; W2 = d["fc2.weight"]; B2 = d["fc2.bias"]
H = len(B1)

def ref(img):
    x = [v / 255.0 for v in img]
    h = [max(sum(x[k] * W1[i][k] for k in range(784)) + B1[i], 0.0) for i in range(H)]
    y = [sum(h[i] * W2[j][i] for i in range(H)) + B2[j] for j in range(10)]
    return y.index(max(y))

N = 24
images = [bytes(784), bytes([255]) * 784]
r = random.Random(7000)
for i in range(N - 2):
    images.append(bytes(r.randint(0, 255) for _ in range(784)))
ok = 0
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