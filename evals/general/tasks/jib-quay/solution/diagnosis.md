# jib-quay — root-cause diagnosis: the transfer-hub deadlock

## Symptom / reproduction

With the SHIPPED service (`/app/service.py`, byte-identical reference at
`/opt/pristine/service.py`) the serial run completes:

    python3 /app/driver.py --service /app/service.py --ledger /app/ledger.json \
        --mix /app/mix_visible.json --port 8765 --serial --out /tmp/serial.json
      -> completes 12 transfers, exit 0

but the concurrent run (the mix's 3 clients) hangs forever:

    python3 /app/driver.py --service /app/service.py --ledger /app/ledger.json \
        --mix /app/mix_visible.json --port 8766 --out /tmp/concurrent.json
      -> STALL: only 2 of 12 responses arrive, then nothing ever again

The hub stops answering every connection because every handler thread is
blocked inside `apply_transfer`.

## Root cause

`TransferHub.apply_transfer` acquires the two per-account locks in the
order `(src, dst)`.  Two transfers that move money between the SAME pair of
accounts in opposite directions therefore acquire the pair in opposite
orders:

  - `TRANSFER alice bob 12000`    locks alice, then bob
  - `TRANSFER bob alice 8000`     locks bob, then alice

Each transfer also holds its first lock ACROSS the simulated FX rate-feed
step (`time.sleep(self.latency)` in `apply_transfer`, before the destination
lock is taken).  When both requests are in flight at the same time — which
the 3-client start barrier in the driver makes a near-certainty — the first
holds alice and waits for bob while the second holds bob and waits for
alice.  Neither can ever proceed: a textbook lock-ordering inversion
(deadlock).  The wait is on `threading.Lock.acquire`, which is not
interruptible, so the hang is permanent and blocks even later requests that
touch those accounts.

The defect is timing-dependent in principle and deterministic in practice:
the `--latency` window makes the "hold first lock, want second lock" state
lasting, so the interleaving reproduces on essentially every concurrent run
of the visible mix and of the grader's hidden mixes.

## Fix applied

`apply_transfer` now takes its two account locks in ONE canonical order —
the accounts sorted by identifier — regardless of transfer direction
(`first, second = sorted((src, dst))`).  The bookkeeping is unchanged: `<src>`
is still debited and `<dst>` still credited, the conversion formula is
unchanged, and transfers on disjoint pairs still run concurrently.  Lock
ordering guarantees that two transfers touching the same pair always line up
in the same order, so no wait cycle can form.  No global lock was added;
the per-account granularity (and with it the concurrency floor) is intact.

## Verification after the repair

- concurrent run of the visible mix completes: 12/12 responses, exit 0;
- balances and journal match a deterministic replay of the mix against the
  ledger (all transfers applied exactly once, no lost or duplicated entry);
- a single transfer still takes ~`--latency` seconds (FX step not removed);
- concurrent throughput is far better than serial throughput, so the service
  is not reduced to one big lock or a single-threaded server.