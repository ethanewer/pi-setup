FROM bench-base:python-3.12

WORKDIR /app

# Site configuration templates (placeholders to be filled by the operator),
# and the shipped Kelpline daemon program.
COPY files/conf/ /app/conf/
COPY files/bin/ /app/bin/

RUN chmod +x /app/bin/kelp_daemon.py && mkdir -p /app/run
