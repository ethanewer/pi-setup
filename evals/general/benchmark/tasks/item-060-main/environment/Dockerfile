FROM bench-base:python-3.12

RUN pip install --no-cache-dir torch && rm -rf /root/.cache/pip

WORKDIR /app
COPY files/ /app/
RUN python3 /app/gen_base.py && rm -f /app/gen_base.py && mkdir -p /app/output /app/models