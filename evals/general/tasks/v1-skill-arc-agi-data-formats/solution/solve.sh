#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{"first_train_input_rows": 2, "first_train_input_cols": 3, "first_train_input_colors": [0, 1, 2], "num_train_examples": 2, "num_test_examples": 1}
EOF
echo "wrote answer.json"