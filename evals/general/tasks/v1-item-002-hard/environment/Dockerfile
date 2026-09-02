FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy pandas

RUN mkdir -p /workspace/data

COPY files/ /app/

RUN python3 /app/gen_data.py