FROM bench-base:python-3.12

RUN pip install --no-cache-dir numpy scipy pandas scikit-learn joblib hydra-core

WORKDIR /app

COPY files/ /app/