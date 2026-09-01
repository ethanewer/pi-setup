#!/bin/bash
# Oracle for saffron-rune: install the deliverable featurizer module, then RUN
# it over the visible catalog to produce /app/features.npz. Never reads /tests.
set -euo pipefail

install -m 0644 /solution/featurize.py /app/featurize.py

# Run the featurizer over /app/molecules.csv; it writes /app/features.npz.
python3 /app/featurize.py
ls -l /app/featurize.py /app/features.npz

echo "oracle ok"
