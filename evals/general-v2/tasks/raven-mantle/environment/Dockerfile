FROM bench-base:python-3.12

WORKDIR /app

# ML toolchain: pinned baseline. CPU-only inference; the "pretrained" engine is
# a local checkpoint committed at build time (no internet at run time).
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1 \
    tokenizers \
    numpy

# Vendor generator: builds the local transformer+tokenizer engine, the runtime
# config, and the shipped input fixtures (all baked into the image).
COPY files/ /app/
RUN python3 /app/gen_vendor.py && rm -f /app/gen_vendor.py

# Sanity: toolchain plus the committed local engine are present.
RUN python3 -c "import torch, transformers, tokenizers, numpy; print('ml-toolchain-ok')"
RUN python3 -c "import os, json; c=json.load(open('/app/config.json')); \
assert os.path.isdir('/app/engine/model') and os.path.isdir('/app/engine/tokenizer'); \
assert c['engine']=='raven-v1'; print('rave-vendor-ok')"

WORKDIR /app