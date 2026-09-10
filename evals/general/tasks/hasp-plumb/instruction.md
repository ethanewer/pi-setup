# Build the real Redis server from source and operate it

This task puts you inside a real production codebase you did not write: the
actual Redis source tree. You must compile it, configure it, and run it so
that it satisfies a concrete operational contract — the kind of survivable
server an engineer would actually deploy.

## Environment

- `/app/src` is a working copy of the real Redis tree, tag `8.10.1`,
  pinned to commit `3399357e7c17b668289386b8a15a3037bc4527b1` (shallow
  clone). The tree is complete and editable.
- The C toolchain is installed (gcc, make). **There is no network** in this
  container: you cannot re-clone, `apt-get install` anything, or download
  anything. Everything you need is already here.
- Nothing has been compiled for you: `/app/src/src/` does not yet contain
  the `redis-server` or `redis-cli` binaries.

## Your job

**1. Build.** Build the server and the command-line client from the source
tree with `make` (one CPU is fine, e.g. `make -j1 redis-server redis-cli`
from `/app/src`). The binaries you need will land in `/app/src/src/`
(`/app/src/src/redis-server` and `/app/src/src/redis-cli`). The client and
the server must be the ones you just built; the evaluator drives the server
exclusively through `/app/src/src/redis-cli`.

**2. Configure.** Write `/app/redis.conf` — a complete, self-contained
server configuration, applied by starting Redis with that config file as
its only argument. Your configuration must make the running server satisfy
all of the following, all verified against the live server at
`127.0.0.1:6379`:

- (Persistence) The server keeps all of its data on disk under the single
  directory `/app/data`. A write that the server has acknowledged must still
  be present after the evaluator kills the server process with `SIGKILL`
  (not a graceful shutdown) roughly a second later and starts it again.
  Surviving a hard kill is a requirement: a shutdown-time-only save is not
  enough.
- (Memory bound + eviction) The server must enforce a memory ceiling of its
  own choosing **in the tens of megabytes** (32–128 MB is a sensible range)
  and, once the ceiling is exceeded, it must keep the workspace usable:
  new writes must still succeed, the server must remove older entries
  (evict) instead of rejecting the writes or running out of memory, and it
  must keep its memory bounded near the ceiling. The keys in the
  evaluator's workloads carry **no expiry** — the server must evict them
  anyway, and by *oldest first* (the most recently written entries survive;
  the oldest don't).
- (Stability) The server must start cleanly, repeatedly, and stay up across
  restarts; two restarts in a row must both work.

**3. Ship a run script.** Write `/app/start.sh`, an executable shell script
that:
- starts the server on `127.0.0.1:6379` with **your** `/app/redis.conf`,
- returns (exits 0) only once the server answers `PING` through
  `/app/src/src/redis-cli`,
- is safe to run again — if a server is already running it must first stop
  it, then start a fresh instance.

The evaluator will run `/app/start.sh` itself, repeatedly and after it
has killed the server, so it is your entry point into the task: everything
that must behave (persistence, eviction, stability) is what the evaluator
drives through it.

## Deliverables

- `/app/redis.conf` — your server configuration,
- `/app/start.sh` — your executable start script,
- `/app/src/src/redis-server` and `/app/src/src/redis-cli` — the binaries
  you built from `/app/src`,
- `/app/data` — the data directory configured into the server.

Not acceptable: a script that re-configures or patches the server into a
different behaviour at start time; a config that points the data directory
to the wrong place; binaries taken from anywhere other than `/app/src`.

## Constraints

- Do not modify the Redis source in a way that changes the datastore's
  semantics or reports a false version (a patched binary is not the task).
  Patching `Makefile` or build flags to skip parts of the build is fine.
- Do not run the full Redis test suite (`make test` pulls it in) — it is
  heavy and is not what the evaluator uses. The evaluator verifies the
  server's behaviour through the client, as described above.
- No network. The trial is fully offline; everything you need is already in
  the image.