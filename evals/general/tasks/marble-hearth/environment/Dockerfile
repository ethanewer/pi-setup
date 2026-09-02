FROM bench-base:python-3.12

WORKDIR /app

# The platform-pinned ML toolchain: the immutable baseline this appliance must
# preserve bit-for-bit (offline_load-style consumers are wired to these exact
# versions).
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

COPY files/ /app/

# Deterministically materialize the visible model store with the pinned
# toolchain and a fixed seed, then drop the generator scaffolding.
RUN python3 /app/tools/gen_model.py /app/model_store/hearth-mini 11 "$(cat /app/tools/vocab_hearth_mini.csv)" \
    && rm -rf /app/tools
