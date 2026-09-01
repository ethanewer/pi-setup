# Meridian Coast Research Station — telemetry rendezvous cluster

You are the site reliability engineer for **Meridian Coast Research Station**. The
station runs a single-node edge *rendezvous cluster* that ingests ocean-sensor
flow telemetry, runs distributed analytics, and serves alerts and exports. Your
job is to (re)build and prove the cluster so that every subsystem it claims is up
actually works and survives re-checking on new data.

All work happens in `/app`. Python 3.12, `gcc`/`mpicc`/`mpirun`, `torch` (CPU),
`aws` CLI, `boto3`, `moto_server`, `postfix` and the `mlmmj` mailing-list daemon
are pre-installed. You may use them freely. Do **not** modify anything under
`/app/protocol/` — those sources are for you to study only. You never see `tests/`.

## Deliverables

Create exactly these three artifacts in `/app/`:

1. **`/app/mpi_main.c`** — a real MPI C program (see §1). You must also compile it
   (`mpicc -O2 /app/mpi_main.c -o /app/mpi_agg`).
2. **`/app/markers/`** — a directory of marker files written by the worker
   processes themselves (see §1 and §2). Proves that real worker processes ran.
3. **`/app/serve.py`** — an executable Python control program with the exact
   subcommand contract in §3. It is a *general* tool: it is re-run on new inputs
   of the same formats, so do not special-case the sample data.

---

## §1. MPI flow-count aggregator (`mpi_main.c`)

A parallel workload that must give **identical results whether run serially or
across many MPI ranks** ("parallel contigs equal serial").

**Usage:** `mpi_agg <fragments.txt> <outdir>` under mpirun.

**Input** `fragments.txt`: one line per observation, `CONTIG_ID<TAB>VALUE` (both
integers). Contigs are unrelated sub-jobs; any contig id may appear many times.

**Work distribution:** rank `r` owns every contig whose `id % size == r` (use a
non-negative modulus). Each rank aggregates the observations it owns — for each
owned contig, `count` (how many lines) and `sum` (total of values) — and writes
`<outdir>/flows.rank<r>.txt` with one line per owned contig, ascending by id:
`<id><TAB><count><TAB><sum>`. Rank 0 must read the file and `MPI_Send` each other
rank its owned lines (real message passing; not just re-reading the file on every
rank).

**Worker markers:** every rank must also write `/app/markers/mpi_rank<r>.marker`
(a small file proving that worker executed).

**Serial==parallel:** running `-np 1` (rank 0 owns everything) must produce
exactly the same multi-line result as concatenating the rank files of `-np 4` and
sorting them. If your distribution or aggregation is wrong, the two won't match.

The verifier re-runs this on fresh fragment files with different contig id sets.

## §2. Marker directory

`/app/markers/` must contain markers written by the *worker processes*:
- `mpi_rank<R>.marker` from every MPI rank (§1), and
- `gloo_rank<R>.marker` from every gloo worker rank (§3, `train-gloo`).
- `s3_<bucket>.ok` and `mail_<list>.ok` confirmation files (from `make-bucket`
  and `mail-init` below).

Any additional marker files are allowed.

## §3. `serve.py` subcommand contract

`python3 /app/serve.py <subcommand> ...`. Each subcommand is an independent,
re-runnable unit. Implement all of the following.

### `train-gloo --world N`
Run a **multi-process distributed aggregation under the gloo backend**. Spawn
`N` worker processes (use `torch.multiprocessing.spawn` with a spawn-joined
process group, guarded so spawned children do not re-enter the dispatcher).
Each worker rank `r`:
- joins a `gloo` process group on `127.0.0.1:29501`;
- builds a **local CPU tensor** carrying value `(r+1)*3` after moving it from
  `int64` to `float32` on the `cpu` device (proper device/dtype movement);
- all-reduces it with `SUM`;
- writes `/app/markers/gloo_rank<r>.marker` and, on rank 0, prints
  `GLOO_SUM=<the all-reduced total>` to stdout.

The all-reduced total is the serial sum of all contributions. The verifier runs
this with hidden world sizes `N` and checks the printed sum AND that all `N`
worker markers appeared. A wrong backend, a missing spawn `__main__` guard, or a
dtype/device mistake will hang or fail.

### `export-netflow --in <flowfile> --out <binfile>`
Read `<flowfile>` (lines `SRCIP,DSTIP,SRCPORT,DSTPORT,PROTO,PKTS,OCTETS`) and
serialize them as one or more **binary NetFlow v5 export datagrams** written to
`<binfile>`.

Header (24 bytes, big-endian): `version=5`, `count`, `SysUptime`, `Unix_secs`,
`Unix_nsecs`, `flow_sequence`, `engine_type=0`, `engine_id=0`, `sampling=0`.

Use these fixed timing fields and derived per-record times:
- `SysUptime = 3000000`, `Unix_secs = 1700000000`, `Unix_nsecs = 0`.
- For a datagram with `n` records, record `i` (0-based): `first = 3000000 -
  (n-i)*500`, `last = 3000000 - (n-1-i)*200` (so `first < last`).
- `flow_sequence` starts at `1` for the first datagram and increments per
  datagram. If there are more than 30 records, split into multiple datagrams of
  at most 30 each.

Each 48-byte record (big-endian): `srcaddr`(4, network order), `dstaddr`(4),
`nexthop=0`(4), `input=0`(2), `output=0`(2), `dPkts`(4), `dOctets`(4),
`first`(4), `last`(4), `srcport`(2), `dstport`(2), `pad1=0`(1), `tcp_flags=0x10`(1),
`prot`(1), `tos=0`(1), `src_as=0`(2), `dst_as=0`(2), `src_mask=0`(1),
`dst_mask=0`(1), `pad2=0`(2).

The verifier parses the bytes with its own NetFlow v5 reader and checks the
header version/count/sequence/timestamps and every flow field against the input,
so an off-by-one in the layout, a byte-swapped address, or a wrong timestamp
fails every hidden case.

### `fetch-flows --port P --out <outfile>`
A **reverse-engineered client** for the Meridian-7 binary telemetry protocol that
the rendezvous server speaks. The server binary is `/app/protocol_server`
(compile it yourself with `gcc /app/protocol/server.c -o /app/protocol_server
-lssl -lcrypto`; source is at `/app/protocol/server.c`). `/app/protocol/client.c`
is a reference client.

Study both sources to determine the exact **handshake, framing, and
authentication message format**, then implement a client that connects to
`127.0.0.1:<port>`, completes the handshake and authentication, requests the flow
records, and writes them (one flow line per line, in server order) to `<outfile>`,
printing `FETCHED <n>` to stdout.

Hint: frames are `[1-byte opcode][2-byte big-endian length][payload]`. The
authentication payload is derived from a fixed shared secret combined with a
per-connection nonce the server sends. Get the opcodes, framing, and auth hash
exactly right — the server rejects anything else. The verifier runs the server
with **different flow data** (same protocol) on a fresh port and checks that your
client retrieves exactly those records.

### `make-bucket --name <bucket> [--port P]`
Create an S3 bucket on the **local emulated object-store endpoint**. Start
`moto_server` on `127.0.0.1:<P>` (default `5660`), set the standard test AWS
credentials and region `us-east-1`, and use the **AWS CLI** (`aws
--endpoint-url http://127.0.0.1:<P> ...`) to create a bucket named `<bucket>`.
Then list the endpoint's buckets and confirm `<bucket>` appears. Print
`BUCKET <bucket> CREATED`, then the listing. You may stop the emulator afterward.

The verifier re-runs this with hidden bucket names and checks both the printed
confirmation and that the name appears in the endpoint's bucket list. Creating
with the wrong endpoint, region, or name will not make it listed.

### `mail-init --list <name>`
Bring up the **mailing-list server stack**: start `postfix` (if not already
running) and create an `mlmmj` mailing list at `/var/spool/mlmmj/<name>` owned by
`nobody`. Configure postfix so mail addressed to `name@localhost` is routed to
the list processor by adding/compiling an alias
`name: "|/usr/bin/mlmmj-receive -L /var/spool/mlmmj/<name>", nobody` and running
`newaliases`. Print `MAIL list <name> up`.

The verifier (a) confirms postfix is running, (b) confirms the list directory
with its canonical structure (`control/`, `text/`, `incoming/`, `index`, ...)
exists, (c) confirms the compiled alias routes to `mlmmj-receive -L <listdir>`,
and (d) feeds a raw message into that exact `mlmmj-receive` command and confirms
it is accepted into the list's `incoming/`. Without the MTA up, the list
initialized, or routing configured to the list processor, these checks fail.

---

## General rules

- `serve.py` must be executable and handle each subcommand cleanly on new inputs.
- Compile and run your own work; do not hard-code the sample results.
- Do not read `/tests/`, do not modify `/app/protocol/` sources, and do not leave
  the cluster in a broken state. Services may be stopped after they have proved
  themselves, except the mailing-list/postfix check expects the stack reachable.
- Edge cases the hidden inputs probe: empty/1-record/6-record flow sets, contig
  ids that assign to different ranks, world sizes of 5/6/7, arbitrary bucket and
  list names. Everything must generalize.
