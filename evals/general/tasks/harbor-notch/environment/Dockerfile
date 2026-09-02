FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends build-essential valgrind \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Keep pristine copies of the protected files for the verifier's hygiene check.
RUN mkdir -p /opt/frozen \
 && cp -r /app/src /opt/frozen/src \
 && cp -r /app/data /opt/frozen/data
