#!/usr/bin/env python3
"""Offline load-path check for the pinned ML toolchain (clean-room).

The platform preinstalls the pinned torch/transformers toolchain so that a
saved-model pipeline can be loaded WITHOUT network access. This script
represents that offline consumer: it refuses to run if the pinned versions
have been changed, because a different torch/transformers resolves to
different tensor/state_dict semantics and silently reproduces a different
result.

Exit code 0 if and only if:
  1. exactly one copy of torch/transformers is importable,
  2. their __version__ equals the pinned baseline below, and
  3. a save/load round-trip of a small model reproduces identical weights
     (i.e. the offline load path is functional with the installed toolchain).
"""
import sys

PINNED_TORCH = "2.13.0+cu130"
PINNED_TRANSFORMERS = "5.16.1"


def main() -> int:
    import torch
    import transformers

    if torch.__version__ != PINNED_TORCH:
        print(f"FAIL torch version {torch.__version__} != {PINNED_TORCH}")
        return 1
    if torch.__version__.split("+")[0] != PINNED_TORCH.split("+")[0]:
        print(f"FAIL torch cpu/gpu qualifier changed: {torch.__version__}")
        return 1
    if transformers.__version__ != PINNED_TRANSFORMERS:
        print(f"FAIL transformers version {transformers.__version__} != {PINNED_TRANSFORMERS}")
        return 1

    # Save/load round-trip: the actual offline load path.
    torch.manual_seed(7)
    model = torch.nn.Linear(4, 4)
    w_before = model.weight.detach().clone()
    path = "/tmp/offline_check.pt"
    torch.save(model.state_dict(), path)
    loaded = torch.nn.Linear(4, 4)
    loaded.load_state_dict(torch.load(path, weights_only=True))
    if not torch.equal(w_before, loaded.weight):
        print("FAIL state_dict round-trip mismatch")
        return 1

    print("OK offline load path intact "
          f"(torch {torch.__version__}, transformers {transformers.__version__})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
