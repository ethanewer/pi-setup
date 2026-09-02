FROM bench-base:python-3.12

RUN pip install --no-cache-dir \
    scikit-learn \
    scipy \
    pandas \
    hydra-core \
    joblib \
    pyyaml

WORKDIR /app
COPY files/ /app/