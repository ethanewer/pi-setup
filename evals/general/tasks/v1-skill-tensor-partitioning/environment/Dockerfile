FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir --no-input numpy

COPY files/make_data.py /app/make_data.py
RUN python3 /app/make_data.py