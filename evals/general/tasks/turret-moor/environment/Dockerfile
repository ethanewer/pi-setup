# turret-moor -- yt upstream-clone scientific analysis task
FROM bench-base:python-3.12

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends git gcc g++ \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email build@localhost \
 && git config --system user.name build

# yt 4.4.2 = tag yt-4.4.2, resolved f043ac898105a5b87da92226813fda96d76050da on 2026-09-10
ARG UPSTREAM_SHA=f043ac898105a5b87da92226813fda96d76050da
RUN git clone --depth 1 --branch yt-4.4.2 https://github.com/yt-project/yt.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# runtime + build dependencies, all pinned.  ewah-bool-utils==1.2.2 is the
# last release whose wheel ships the .pxd files the yt Cython build cimports.
RUN pip install --no-cache-dir numpy==2.5.3 cython==3.0.12 setuptools==84.0.0 ewah-bool-utils==1.2.2 cmyt==2.0.2 matplotlib==3.11.1 more-itertools==11.1.0 packaging==26.3 pillow==12.3.0 tomli-w==1.2.0 tqdm==4.70.0 unyt==3.1.0

# build the clone's Cython extensions in place so `import yt` IS the tree
RUN cd /app/src && pip install --no-cache-dir --no-deps --no-build-isolation -e .

WORKDIR /app

# authored fixture + generator; upstream source bytes never enter this tree
COPY files/ /app/