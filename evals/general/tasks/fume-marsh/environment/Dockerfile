FROM bench-base:python-3.12

RUN pip install --no-cache-dir numpy scikit-learn joblib

WORKDIR /app

RUN mkdir -p /app/data /logs
COPY files/pump_readings.csv /app/data/pump_readings.csv

CMD ["/bin/bash"]
