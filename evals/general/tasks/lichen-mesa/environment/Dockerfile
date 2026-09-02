FROM bench-base:python-3.12

WORKDIR /app

# lichen-mesa: CPU-only distilled-SAM segmentation over survey tiles.
# torch CPU wheel + numpy + pillow (PNG decode). Deterministic fixture
# generation; no network needed at run or verify time.
RUN pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu \
        torch numpy pillow

COPY files/ /app/

# Visible survey tile (hidden tiles are generated from the same deterministic
# generator with different seeds at authoring time).
RUN python3 /app/gen_tile.py --seed 101 --name tile_alpha --out /app/survey/tile_alpha

ENV PYTHONUNBUFFERED=1
