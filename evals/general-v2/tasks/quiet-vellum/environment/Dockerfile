FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# quiet-vellum service accounts, all locked with a non-login shell.
RUN useradd -m -s /usr/sbin/nologin nightlog \
 && useradd -m -s /usr/sbin/nologin quartermaster \
 && useradd -m -s /usr/sbin/nologin coxswain
