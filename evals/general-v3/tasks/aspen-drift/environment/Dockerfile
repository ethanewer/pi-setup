FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch plus the data stack used by the pipeline and the verifier.
RUN pip install --no-cache-dir --disable-pip-version-check numpy pandas \
 && pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by trainer, evaluator and verifier.
ENV ASPEN_FEATURES=6 ASPEN_WIDTH=24 ASPEN_CLASSES=1

# Provided fixtures (train/holdout CSVs).
COPY files/ /app/
