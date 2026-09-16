FROM bench-base:python-3.12

# The environment declares cpus = 1; DuckDB is told `SET threads=1` by the
# pipeline itself, and the numeric runtime pins below keep any auxiliary
# thread pools inside the same single-CPU budget.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install --no-cache-dir duckdb==1.5.5

WORKDIR /app

COPY files/ /app/

# Build the ~630 MB Hive-partitioned Parquet warehouse (12 monthly partitions,
# 48M fact rows) deterministically at image-build time. duckdb's scratch copy
# stays inside this layer; it streams row-group by row-group, so build memory
# stays low. The generator is removed afterwards: /app/warehouse is the agent's
# read-only input, and the fixture is reproducible from environment/files.
RUN python3 /app/gen_warehouse.py /app/warehouse \
        2024-01,2024-02,2024-03,2024-04,2024-05,2024-06,2024-07,2024-08,2024-09,2024-10,2024-11,2024-12 \
        20240101 \
 && python3 -c "import glob,os; print('warehouse MB:', sum(os.path.getsize(f) for f in glob.glob('/app/warehouse/**/*.parquet', recursive=True)) // 1048576)" \
 && rm -f /app/gen_warehouse.py