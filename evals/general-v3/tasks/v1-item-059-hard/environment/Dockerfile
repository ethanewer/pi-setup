FROM bench-base:python-3.12

RUN pip install --no-cache-dir pypiserver build setuptools wheel && rm -rf /root/.cache/pip

WORKDIR /app
COPY files/ /app/