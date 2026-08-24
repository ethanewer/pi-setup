FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir tokenizers

COPY files/tokenizer /app/tokenizer
COPY files/text.txt /app/text.txt
