# Prism Bridge: distributed service-cluster bring-up

Prism Bridge runs a small distributed service cluster on one machine. The cluster
has three parts: an MPI read-joiner that assembles fragments into contigs, a
partitioned file hashing service that runs in real worker processes and leaves
observable markers, and the pinned Hadoop and JVM toolchain the cluster reports on.
You bring all three up and leave the system in a usable state.

Work in `/app`. The environment already has `gcc`, OpenMPI (`mpicc`, `mpirun`),
`python3`, and `curl`. A visible dataset ships with the image under
`/app/sample/`.

## Deliverables (exact paths)

1. `/app/mpi_main.c` - an MPI contig assembler (spec below).
2. `/app/serve.py` - the partition hashing service + status probe (spec below).
3. `/app/markers/` - a directory holding the three worker marker files the
   hashing service produces.

In addition, install the pinned toolchain (below) into the live cluster so it is
present and version-correct after you finish. The verifier checks every
deliverable and the toolchain on its own copies of inputs, so leave working
generators, not just output for the sample.

## The MPI contig assembler (`/app/mpi_main.c`)

The sampler emits fragments. Each fragment is one line of text:

```
CHAIN_ID<TAB>FRAGMENT
```

A chain id is a non-negative integer. Fragments of the same chain are fragments
of one longer sequence; overlapping suffixes and prefixes join them. A `.c`
source at `/app/mpi_main.c` must compile with `mpicc` and run under the MPI
launcher as:

```
mpi_program <input.txt> <outdir>
```

The program:

- groups fragments by chain id;
- assembles each chain into one or more contigs by repeatedly joining the pair of
  pieces that share the longest suffix/prefix overlap (ties broken deterministically,
  for example by piece order). Pieces with no overlap stay separate. Fragments must
  never be dropped: the set of contigs you emit is exactly what the overlapped
  fragments spell out;
- distributes chains across ranks so each rank owns a fixed subset, e.g. rank r
  owns the chains where `chain_id % nrank == r`. Rank 0 reads the input and hands
  each other rank its subset over MPI;
- each rank writes its assembled contigs to `<outdir>/contigs.rank<N>.txt`, one
  contig per line.

The verifier compiles `/app/mpi_main.c` itself with `mpicc` and runs it on each
dataset twice: once with `-np 1` and once with `-np 4`, using
`mpirun --allow-run-as-root --oversubscribe`. It requires that, for every dataset,
the set of contigs across all ranks at `np=1` equals the set at `np=4`, and that
all four ranks wrote at least one non-empty piece of output. So the split and the
assembly must be genuinely parallel (each rank takes a distinct subset) and the
result must be identical to the single-rank run. `mpirun` refuses to run as root by
default; keep the flag `--allow-run-as-root` (and `--oversubscribe` if needed) when
you invoke the compiled program during development.

The visible sample is `/app/sample/reads.mpi.txt`. Build the general tool and
verify it on that sample; the verifier then recompiles it and runs it on other
datasets it holds.

### The parallel hashing service (`/app/serve.py`)

`/app/serve.py` has two modes.

Mode 1, the file hash partition:

```
python3 /app/serve.py <input_dir> <manifest_path>
```

For every top-level regular file in `<input_dir>` it computes a PBKDF2 digest and
writes one line per file to `<manifest_path>`, sorted by basename (lexicographic):

```
<basename>\t<hexdigest>
```

The digest is a PBKDF2-HMAC-SHA256 derivation with 60000 iterations, password =
the raw file bytes, salt = `sha256(basename-as-bytes)` (hex-encoded result).
Do not truncate the digest; use the full 64 hex chars. Empty files are allowed and
must digest to their value, not error.

The hashing must run in real worker processes, not threads. Send the per-file jobs
to a `ProcessPoolExecutor`. Same for any hidden input set: the service must be
reusable, not hardcoded to the sample.

After hashing, the service creates exactly three marker files under
`/app/markers/`, each non-empty:

- `STARTED.marker`
- `WORKERS.marker` - one `worker <pid>` line per distinct worker process that
  ran a job. At least two distinct worker process ids must be listed.
- `COMPLETED.marker`

`/app/serve.py` must terminate with exit code 0 on success after both the
manifest and the markers are fully written.

Mode 2, the status probe:

```
python3 /app/serve.py --status
```

prints two lines:

```
java <major.minor>
hadoop <release>
```

where `<major.minor>` is the installed java version major.minor and `<release>` is
the installed hadoop release. It exits 0 only when both are detected.

## The pinned toolchain (java 11 + Hadoop 3.3.6)

Install a java 11 runtime (`openjdk-11-jre-headless` from apt works) and a pinned
Hadoop **3.3.6** tree under `/opt` so that `/opt/hadoop` resolves to the
`hadoop-3.3.6` install. After you finish:

- `java -version` reports major version 11;
- `JAVA_HOME=<jdkdir> /opt/hadoop/bin/hadoop version` reports `Hadoop 3.3.6`;
- `python3 /app/serve.py --status` prints those two versions (major.minor for
  java, exactly `3.3.6` for hadoop).

A verified copy of the pinned release tarball is pre-staged inside the
container at `/opt/hadoop-3.3.6.tar.gz` (sha512 next to it at
`/opt/hadoop-3.3.6.tar.gz.sha512`). Prefer extracting from it — the upstream
mirror is slow and unreliable under load:

```bash
tar -xzf /opt/hadoop-3.3.6.tar.gz -C /opt
ln -sf /opt/hadoop-3.3.6 /opt/hadoop
```

(You may also fetch it yourself with `curl -fsSL -o /tmp/hadoop.tar.gz
https://archive.apache.org/dist/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz`
and extract; either way the end state must be exactly `/opt/hadoop` resolving
to a `hadoop-3.3.6` install.)

Make sure `serve.py --status` can find java on `PATH` and the hadoop tree under
`/opt/hadoop`.

## What must stay intact

- Work in `/app`. Touch `/opt` only for the hadoop/Java install. Do not change the
  `/app/sample/*` fixtures.
- Do not put test data or verifier knowledge into the deliverables; they must be
  general programs.
- Do not leave state that pretends to be the verifier's hidden data.

## Recommended end-to-end check

Before finishing, run:

```bash
cd /app
mpicc -O2 /app/mpi_main.c -o /app/mpi_sim
mkdir -p /app/self/ser /app/self/par
mpirun --allow-run-as-root --oversubscribe -np 1 /app/mpi_sim /app/sample/reads.mpi.txt /app/self/ser
mpirun --allow-run-as-root --oversubscribe -np 4 /app/mpi_sim /app/sample/reads.mpi.txt /app/self/par
python3 /app/serve.py /app/sample/files /app/manifest.txt
python3 /app/serve.py --status
```

Check that the union of the serial contig files equals the union of the four
parallel rank files, and that `/app/markers/` holds `STARTED.marker`,
`WORKERS.marker`, `COMPLETED.marker`. `serve.py` must also have created those
markers when it processed the sample.