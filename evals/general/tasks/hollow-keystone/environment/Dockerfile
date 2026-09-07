FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends build-essential git valgrind patch \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Build the merge repository (/app/devzone) with two divergent branches that
# share a common ancestor, and keep a pristine copy of the merge-base working
# tree under /opt/frozen/base for the verifier to apply the merged.diff onto.
# A later RUN in this file builds a git repository, so it is root-owned, and git
# refuses to operate on a repository owned by another user: it exits 128 with
# "detected dubious ownership". Whether the trial works then depends on which
# user the harness runs it as. Record the exception in /etc/gitconfig rather
# than root's ~/.gitconfig so it holds for every user, and use the wildcard
# because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*'
RUN git config --global user.email "arena@keystone.local" \
 && git config --global user.name "Keystone Arena" \
 && mkdir -p /app/devzone \
 && cd /app/devzone \
 && git init -q \
 && printf '[profile]\nbuffer = 64\nmode = "auto"\n' > config.toml \
 && printf 'server=4.2.1\ncache=2.3.0\n' > deps.txt \
 && printf 'keystone osslet merge exercise\n' > NOTES.md \
 && mkdir -p /opt/frozen/base \
 && cp config.toml /opt/frozen/base/ \
 && cp deps.txt /opt/frozen/base/ \
 && cp NOTES.md /opt/frozen/base/ \
 && git add -A \
 && git commit -qm 'base snapshot' \
 && git branch rel-main \
 && git checkout -qb feat-stream \
 && sed -i 's/buffer = 64/buffer = 256/' config.toml \
 && sed -i '/mode = "auto"/a stream = true' config.toml \
 && printf 'server=4.2.1\ncache=2.6.0\nmonitor=9.7.2\n' > deps.txt \
 && git add -A \
 && git commit -qm 'streaming feature' \
 && git checkout -q rel-main \
 && sed -i 's/buffer = 64/buffer = 1024/' config.toml \
 && sed -i 's/mode = "auto"/mode = "turbofan"/' config.toml \
 && printf 'server=4.2.1\ncache=2.9.0\n' > deps.txt \
 && git add -A \
 && git commit -qm 'rel-main hardening' \
 && cd /app \
 && cp -r /app/src /opt/frozen/src \
 && cp sample.conf /opt/frozen/sample.conf
