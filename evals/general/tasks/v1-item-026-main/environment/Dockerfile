FROM bench-base:python-3.12

WORKDIR /app

# Bottle web framework
RUN pip install -q --break-system-packages bottle

COPY files/main.py /app/main.py
COPY files/regression_check.py /app/regression_check.py

WORKDIR /app