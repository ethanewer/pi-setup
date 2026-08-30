FROM bench-base:python-3.12

# Libraries for the deliverable (fetch/verify subcommands) and the verifier.
RUN pip install --no-cache-dir \
        torch==2.5.1 transformers==4.46.3 huggingface_hub==0.26.5 safetensors

ENV HF_HUB_DISABLE_TELEMETRY=1

WORKDIR /app

COPY files/ /app/

RUN chmod +x /app/entrypoint.sh /app/hub_server.py

# Generate the visible repo (ridge/topoline-24m) served by the hub server,
# plus /app/hub_pristine.sha256 for the verifier's no-modify check.
RUN mkdir -p /build && cp /app/gen_model.py /build/gen_model.py \
    && python3 /app/fix_gen.py && rm -rf /build

ENTRYPOINT ["/app/entrypoint.sh"]
