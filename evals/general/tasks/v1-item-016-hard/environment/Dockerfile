FROM bench-base:python-3.12

RUN pip install --quiet datasets==5.0.1 tokenizers==0.23.2 huggingface_hub==1.30.0

WORKDIR /app
COPY files/data /app/data
COPY files/models /app/models