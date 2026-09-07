FROM bench-base:python-3.12

# tar, gzip, file and xxd are used to build, inspect and validate artifacts.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends tar gzip file xxd \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

# credentials.file is the fixture that makes the "exclude anything not
# world-readable" rule fire: the instruction documents it as mode 0600 and the
# reference solver excludes a file precisely when its other-read bit is clear.
# Git records only 100644 and 100755, so a 0600 file cannot be committed; COPY
# lands it world-readable, the exclusion rule never triggers, and the archived
# credentials.file then trips the verifier's name-based exclusion check. The task
# was unsolvable for every agent and for its own oracle. Establish the intended
# mode at build time, where it survives.
RUN chmod 0600 /app/data/credentials.file