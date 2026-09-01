# Velvet Ember Relay — task image (stdlib-only WSGI service).
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Verifier writes the numeric reward here.
RUN mkdir -p /logs/verifier
