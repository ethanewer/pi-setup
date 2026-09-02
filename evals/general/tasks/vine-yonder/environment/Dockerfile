FROM bench-base:python-3.12

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

# JRE for Spark driver/executors (Debian trixie ships OpenJDK 21 runtime).
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-21-jre-headless ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# PySpark (bundled standalone jars, offline), datasets, and HTTP/parquet deps.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        pyspark \
        datasets \
        pandas \
        pyarrow \
        requests \
        flask >/dev/null 2>&1 || \
    python3 -m pip install --no-cache-dir --break-system-packages \
        pyspark requests datasets pandas pyarrow flask >/dev/null 2>&1

# Neural any JVM known-good.
RUN java -version 2>&1 | head -1

COPY files/ /app/

WORKDIR /app