FROM bench-base:python-3.12

WORKDIR /app

# A tiny fixed "embedding model": word -> 4-dim vector, plus two sentences.
RUN python3 - <<'PYEOF'
import json

model = {
    "dim": 4,
    "words": {
        "cat":   [0.8, 0.1, 0.2, 0.0],
        "dog":   [0.9, 0.2, 0.1, 0.1],
        "fish":  [0.2, 0.9, 0.1, 0.0],
        "bird":  [0.1, 0.7, 0.2, 0.3],
        "chase": [0.5, 0.3, 0.8, 0.1],
        "swim":  [0.2, 0.6, 0.7, 0.2],
        "fly":   [0.3, 0.5, 0.9, 0.4],
        "the":   [0.05, 0.05, 0.05, 0.05],
        "a":     [0.04, 0.04, 0.04, 0.04],
    },
    "sentences": {
        "A": ["the", "cat", "chase", "the", "dog"],
        "B": ["the", "bird", "fly", "the", "fish"],
    },
}
with open('/app/embeddings.json', 'w') as f:
    json.dump(model, f, indent=2)
print('wrote embeddings.json')
PYEOF