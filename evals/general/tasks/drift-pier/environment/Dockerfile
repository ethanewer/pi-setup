FROM bench-base:python-3.12

RUN pip install --no-cache-dir pandas numpy >/dev/null 2>&1 && \
    python3 -c "import pandas, numpy"

WORKDIR /app

# Shipped baseline data-mart for the default close-out run.
COPY files/ /app/

ENV PYTHONUNBUFFERED=1