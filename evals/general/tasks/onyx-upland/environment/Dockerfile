FROM bench-base:python-3.12
WORKDIR /app
COPY files/ /app/
RUN pip install --no-cache-dir tomli==2.4.1 >/dev/null 2>&1 || true