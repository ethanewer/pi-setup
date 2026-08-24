#!/bin/bash
set -euo pipefail

cat > /app/info.py <<'EOF'
import json

data = {
    "classes": ["airplane","automobile","bird","cat","deer","dog","frog","horse","ship","truck"],
    "num_classes": 10,
    "image_shape": [32, 32, 3],
    "num_train": 50000,
    "num_test": 10000,
}
json.dump(data, open("/app/cifar_info.json", "w"))
EOF

python3 /app/info.py