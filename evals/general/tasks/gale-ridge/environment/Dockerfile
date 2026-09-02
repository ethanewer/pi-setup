FROM bench-base:python-3.12

WORKDIR /app

# Platform-pinned ML toolchain. The solution/verifier depend on this exact
# stack; the offline cache is local-filesystem only (no GPU, no internet).
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1 \
    safetensors \
    mlflow \
    scikit-learn

# Vendor fixtures: the pretrained-weights generator, the committed pipeline
# config, and the char token vocabulary text.
COPY files/ /app/

# Bake the "pretrained" model into a read-only vendor directory (no internet;
# weights are committed artifacts, not fetched at run time).
RUN python3 /app/gen_vendor.py

# Sanity: toolchain + vendor present.
RUN python3 -c "import torch, transformers, mlflow, sklearn, safetensors; print('ml-toolchain-ok')"
RUN python3 -c "import os; assert os.path.isfile('/app/vendor/bagnet_frozen.pt') and os.path.isfile('/app/vendor/tokens.txt') and os.path.isfile('/app/config.json'); print('vendor-ok')"