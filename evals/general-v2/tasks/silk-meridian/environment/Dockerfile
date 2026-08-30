FROM bench-base:python-3.12

WORKDIR /app

# silk-meridian: revision-pinned embedding + cosine retrieval. numpy only.
RUN pip install --no-cache-dir numpy

COPY files/ /app/

# Visible retrieval bundle (hidden bundles are generated from the same
# deterministic generator with different seeds/revisions at authoring time).
RUN python3 /app/gen_bundle.py --out /app \
      --seed 4141 --name visible --revision meridian-4.2.0 \
      --stale-revision meridian-3.1.4 --stale-seed 909 --n-docs 14

ENV PYTHONUNBUFFERED=1
