FROM bench-base:python-3.12

WORKDIR /app
COPY files/gen_data.py /app/gen_data.py
RUN mkdir -p /app/data && python3 /app/gen_data.py && rm /app/gen_data.py