FROM bench-base:python-3.12

RUN pip install --no-cache-dir pypiserver==2.4.1 build==1.6.0 setuptools==84.0.0 wheel==0.48.0 && rm -rf /root/.cache/pip

WORKDIR /app
COPY files/ /app/