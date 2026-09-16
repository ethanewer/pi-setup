FROM bench-base:ubuntu-24.04

# The task builds a real upstream C suite (shadow) at image build time.
# cpus = 1 everywhere; pin numeric thread pools defensively.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# --- build toolchain ---
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gcc make autoconf automake libtool gettext autopoint bison flex xsltproc \
        pkg-config libcrypt-dev zlib1g-dev libpam0g libnsl-dev libselinux1-dev \
        libaudit-dev libattr1-dev libacl1-dev jq ca-certificates \
        strace \
 && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- pinned upstream clone ----------------------------------------------------
# shadow-maint/shadow, release v4.11.1 (annotated tag object d8f7f88d... peels to
# commit eccf1c56...). The tag must NOT be the pin; the checked-out commit is.
RUN git clone --depth 1 --branch v4.11.1 https://github.com/shadow-maint/shadow.git /opt/shadow-src \
 && cd /opt/shadow-src \
 && test "$(git rev-parse HEAD)" = "eccf1c569c7ac3b9e3b535c91b6ed3c329e9ec8c"

# --- build and install the suite into the canonical system locations ----------
# --without-libpam: classic /etc/shadow authentication, no PAM configs needed.
# --disable-man: skip docbook man page generation (not needed at trial time).
RUN cd /opt/shadow-src \
 && autoreconf -i \
 && ./configure --prefix=/usr --sysconfdir=/etc \
        --without-libpam --without-selinux --without-audit --without-btrfs \
        --without-acl --without-attr --without-skey --without-tcb \
        --without-libcrack --without-nscd --without-sssd --disable-man \
 && make -j1 \
 && make install

# --- self-test the built toolchain, then remove the test account ---------------
RUN /usr/sbin/useradd -m -u 3199 -g nogroup -s /bin/bash smoke-reeve \
 && printf 'smoke-reeve:Pw!smoke123\n' | /usr/sbin/chpasswd -c SHA512 \
 && /usr/bin/chage -M 90 smoke-reeve \
 && grep -qF '$6$' /etc/shadow \
 && /usr/sbin/userdel -r smoke-reeve \
 && rm -rf /home/smoke-reeve

# --- pristine copy of the account databases (the verifier restores these) ------
RUN mkdir -p /opt/reeve-gate/pristine/etc \
 && cp -a /etc/passwd /etc/shadow /etc/group /etc/gshadow /opt/reeve-gate/pristine/etc/

# --- build-time snapshot of the installed account tools -----------------------
# The verifier recomputes these hashes; a mismatch means the tools the agent
# (or anyone) used are not the binaries this image built from the pinned source.
RUN sha256sum \
      /usr/sbin/useradd /usr/sbin/usermod /usr/sbin/userdel \
      /usr/sbin/groupadd /usr/sbin/groupdel /usr/sbin/chpasswd /usr/sbin/newusers \
      /usr/bin/passwd /usr/bin/chage /usr/bin/gpasswd \
    > /opt/reeve-gate/built-bins.sha256

WORKDIR /app

COPY files/ /app/