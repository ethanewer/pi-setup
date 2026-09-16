FROM bench-base:python-3.12

WORKDIR /app

RUN git clone --filter=blob:none --no-checkout https://github.com/pallets/jinja.git /tmp/jinja \
    && git -C /tmp/jinja checkout --detach 5ef70112a1ff19c05324ff889dd30405b1002044 \
    && cp -a /tmp/jinja /app/jinja \
    && rm -rf /app/jinja/.git /tmp/jinja

RUN python -m pip install --no-cache-dir \
    "MarkupSafe==3.0.2" \
    "pytest==8.3.5" \
    "trio==0.29.0"
