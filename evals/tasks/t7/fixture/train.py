#!/usr/bin/env python3
"""Small training run: quiet except for a checkpoint save roughly every 70 s."""
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
    last_ckpt = None
    print("[train] starting run", flush=True)
    while True:
        time.sleep(STEP_TIME)
        step += 100
        loss = max(0.2, loss * r.uniform(0.55, 0.75))
        last_ckpt = f"checkpoint-{NONCE}-{step}.ckpt"
        with open(os.path.join(HERE, last_ckpt), "w") as f:
            f.write(f"step={step} loss={loss:.4f}\n")
        print(f"[train] checkpoint saved: step {step} loss={loss:.4f} file={last_ckpt}", flush=True)
        if time.time() - start >= total:
            break
    with open(os.path.join(HERE, "train_done.json"), "w") as f:
        json.dump({
            "final_checkpoint": last_ckpt,
            "elapsed": round(time.time() - start, 1),
            "nonce": NONCE,
            "seed": SEED,
        }, f)
    print(f"TRAINING COMPLETE final={last_ckpt}", flush=True)


if __name__ == "__main__":
    main()
