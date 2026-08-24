FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy \
 && pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch --break-system-packages \
 && pip install --no-cache-dir sentence-transformers

COPY files/ /app/