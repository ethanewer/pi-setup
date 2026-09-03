FROM bench-base:python-3.12

# Rowan Statute compliance bench: the agent builds a declaration generator
# from raw transaction records. Visible fixtures ship under /app; the
# verifier executes the generator on /app and on hidden workdirs.
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

COPY files/ /app/