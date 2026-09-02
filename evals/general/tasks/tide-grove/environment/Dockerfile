FROM bench-base:python-3.12

WORKDIR /app

# Pinned ML toolchain used by the trainer.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

COPY files/ /app/

# Fixtures are read-only inputs for the task.
RUN chmod -R a-w /app/data /app/train_config.txt \
    && rm -rf /app/tools
