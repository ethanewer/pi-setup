FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends build-essential valgrind \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Pristine copy for the verifier's no-modify checks.
RUN mkdir -p /opt/frozen \
 && cp -r /app/src /opt/frozen/src \
 && cp /app/sample_input.txt /opt/frozen/sample_input.txt
