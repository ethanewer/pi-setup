`/app/worker.py` is a slow, long-running Python script. It performs three steps over time: it sleeps briefly, then signals that it is ready by creating the file `/tmp/worker_ready`, computes a result, does more work, and finally writes that result to `/tmp/worker_result.txt`. It uses input data from `/app/work_data.json`.

Your job is to demonstrate correct handling of a long-running background process and its readiness handshake.

1. Launch `/app/worker.py` as a *background* process so your main script is not blocked by it.
2. Poll (do not assume) until the readiness file `/tmp/worker_ready` exists, so you know the worker is actually up.
3. After the worker is ready, wait until `/tmp/worker_result.txt` appears (the finished output of the worker).
4. Copy the exact contents of `/tmp/worker_result.txt` into `/app/result.txt`.

The result must come from reading the worker's output file — do not recompute the value yourself. Produce `/app/result.txt` containing the worker's value.
