FROM bench-base:python-3.12

WORKDIR /app

# Platform-pinned ML toolchain (offline at run time; no GPU).
RUN pip install --no-cache-dir --disable-pip-version-check torch==2.13.0

COPY files/ /app/

RUN python3 -c "import json,torch; c=json.load(open('/app/config.json')); assert c['feature_dim']==64 and c['num_classes']==5; print('config-ok', torch.__version__)"
