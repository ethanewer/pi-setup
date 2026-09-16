FROM bench-base:python-3.12
ARG UPSTREAM_SHA=ee2642b4fa26e689ba4595067504668bc7a89016
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
RUN apt-get update -y && apt-get install -y --no-install-recommends git build-essential \
 && rm -rf /var/lib/apt/lists/*
# Clone gensim 4.4.0 pinned to an immutable commit; fail closed if the tag moved.
RUN git clone --depth 1 --branch 4.4.0 https://github.com/RaRe-Technologies/gensim.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"
RUN pip install --no-cache-dir setuptools==68.2.2 wheel==0.41.3 cython==0.29.36 pytest==7.4.4 \
 && cd /app/src && pip install --no-cache-dir -e .
COPY files/ /app/
# Regenerate the visible corpus deterministically from the authored generator
# (identical to the committed copy) so the build path exercises the generator.
RUN python3 /app/gen_corpus.py /app/corpus "botany,geology,aviation,medicine" 101 600 \
 && rm -f /app/corpus/keys.json
WORKDIR /app
