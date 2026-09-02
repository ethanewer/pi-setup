FROM bench-base:python-3.12

WORKDIR /app

# Visible fixtures: two corpus files + the protected-term list, read-only.
COPY files/ /app/data/
RUN chmod -R a-w /app/data
