FROM bench-base:python-3.12

# CedarCipher needs numpy (model weights / offline assets) and pyyaml
# (the lm-eval-style harness config). The rest is pure stdlib — no torch,
# no transformers, no tokenizers, no lm-eval. Keeps the image lean and the
# build fast, which matches the clean-room authoring policy (no vendored
# source trees — every program is written by the agent itself).
RUN python3 -m pip install --no-cache-dir --quiet numpy==1.26.4 pyyaml==6.0.1

WORKDIR /app
COPY files/ /app/

CMD ["/bin/bash"]