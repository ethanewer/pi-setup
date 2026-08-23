#!/usr/bin/env python3
"""Small training run: quiet except for a weights write roughly every 70 s.

Line wording deliberately avoids the monitor extension's default notifyOn
tokens (saved, checkpoint, complete, done, ready, ...) so a plain watcher
stays silent and periodic check-ins require heartbeats.
"""
import json
import os
import random
import time

SEED = os.environ.get("SEED", "0")
NONCE = os.environ.get("MB_NONCE", "")
HERE = os.path.dirname(os.path.abspath(__file__))
STEP_TIME = 70


def main():
    r = random.Random(f"{SEED}:t7:train")
    total = r.randint(220, 280)
    start = time.time()
    step = 0
    loss = r.uniform(2.5, 4.0)
    last_weights = None
    while True:
        time.sleep(STEP_TIME)
        step += 100
        loss = max(0.2, loss * r.uniform(0.55, 0.75))
        last_weights = f"weights-{NONCE}-{step}.bin"
        with open(os.path.join(HERE, last_weights), "w") as f:
            f.write(f"step={step} loss={loss:.4f}\n")
        print(f"[train] weights written: step {step} loss={loss:.4f} file={last_weights}", flush=True)
        if time.time() - start >= total:
            break
    with open(os.path.join(HERE, "train_done.json"), "w") as f:
        json.dump({
            "final_weights": last_weights,
            "elapsed": round(time.time() - start, 1),
            "nonce": NONCE,
            "seed": SEED,
        }, f)
    print(f"RUN OVER final={last_weights}", flush=True)


if __name__ == "__main__":
    main()
