# dust-tape — PDP-11 tape-archive triage environment.
# Python-only task; the artifact corpus (PDP-11 a.out blobs, minimal ELF
# images, stubs, text, junk) is generated deterministically at build time.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN python3 /app/tools/gen_artifacts.py --out /app/artifacts \
 && rm -rf /app/tools/__pycache__ \
 && chmod -R a+rX /app

WORKDIR /app
