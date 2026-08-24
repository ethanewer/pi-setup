FROM bench-base:python-3.12

WORKDIR /app

# Deterministic offline tokenizer model + Flask serving stack.
RUN pip install --no-cache-dir flask
RUN pip install --no-cache-dir "transformers>=4.40" "tokenizers>=0.15"

COPY files/ /app/

ENV TRANSFORMERS_OFFLINE=1 \
    HF_HUB_OFFLINE=1 \
    HF_HOME=/app/hf_cache