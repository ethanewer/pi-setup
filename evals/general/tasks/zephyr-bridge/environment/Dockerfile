# zephyr-bridge task image: tokenizer + 300-dim embeddings + fasttext-style
# classifier + metrics + vocab-dataclass shipping bundle.  CPU-only.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    scipy \
    scikit-learn \
    gensim==4.3.3

# shared loader + corpus generator fixtures
COPY files/ /app/

# ship the labeled review corpus for the agent
RUN python3 /app/gen_corpus.py --out /app/data/reviews.tsv --seed 11 --count 2600 --edge 0

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]