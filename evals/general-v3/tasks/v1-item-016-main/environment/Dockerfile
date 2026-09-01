FROM bench-base:python-3.12

RUN pip install --quiet datasets tokenizers huggingface_hub

WORKDIR /app
COPY files/data /app/data
COPY files/models /app/models