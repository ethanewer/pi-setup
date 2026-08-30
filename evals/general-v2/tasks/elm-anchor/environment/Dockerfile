FROM bench-base:python-3.12

WORKDIR /app

# elm-anchor: vocabulary/merge-rule emission for the shipped Merm loader.
# Standard library only.

COPY files/ /app/

# Visible corpus (hidden corpora are generated from the same deterministic
# generator with different seeds at authoring time).
RUN python3 - <<'PY'
import random

rng = random.Random(2024)
pool = [
    "ridge", "ledge", "cleft", "scree", "talus", "moraine", "cirque", "arete",
    "col", "saddle", "bergschrund", "serac", "crevasse", "nunatak", "neve",
    "firn", "ablation", "accumulation", "permafrost", "talik", "pingo",
    "cafe", "naive", "uber", "garcon", "fjord", "smorgasbord", "voila",
    "boulders", "meltwater", "outwash", "esker", "drumlin", "kettle", "kame",
    "till-plain", "erratic42", "hiker's", "waypoint7", "cairn-line",
]
lines = []
for _ in range(90):
    n = rng.randint(6, 14)
    lines.append(" ".join(rng.choice(pool) for _ in range(n)))
with open("/app/data/corpus.txt", "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("corpus written: %d lines" % len(lines))
PY

ENV PYTHONUNBUFFERED=1
