FROM bench-base:python-3.12

WORKDIR /app

# Visible model card (read-only fixture).
COPY files/ /app/
RUN chmod -R a-w /app/model_card.json
