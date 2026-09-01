FROM bench-base:python-3.12

# Data-log-reporting task: parse/tabulate an access log, fix a newline bug in a
# CSV processor, write a bash cluster-state sampler, and produce exact-format
# computed answers. Only stock python + coreutils are needed; pandas kept lean.
RUN pip install --no-cache-dir pandas

WORKDIR /app

COPY files/ /app/

# Bake shipped inputs: access log, buggy CSV script + data, and the cluster
# state probe. Make the probe executable.
RUN chmod 0755 /app/data/cluster_probe