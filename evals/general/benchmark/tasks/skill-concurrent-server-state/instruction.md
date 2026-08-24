A small in-memory server keeps a shared counter `total` and a shared dict `increments`. Concurrent worker threads mutate this shared state. Because the state is shared across threads, updates must be made thread-safely (e.g. guarded by a `threading.Lock`).

Write a program `/app/server.py` that:
1. creates a shared integer `total = 0` and a shared dict `increments = {}`,
2. spawns **4** worker threads (each with a distinct worker id),
3. each worker loops **200** times, and on every iteration performs the two following state updates **inside a single lock-protected block**:
   - `total = total + 1`
   - `increments[worker_id] = increments.get(worker_id, 0) + 1`
4. joins all threads,
5. writes two lines to `/app/state.txt`:
   - `total=<final total>`
   - `keys=<number of distinct worker ids in increments>`

Because every mutating operation runs under one lock, the correct result is `total=800` (4 workers × 200) and `keys=4`. The verifier runs `/app/server.py` independently and checks these exact values.