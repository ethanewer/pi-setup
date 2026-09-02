#!/usr/bin/env python3
"""tundra-ledge verifier.

Modes:
   main   -- validate /app/answer.json and /app/chess_state.pt against
             independently recomputed references.
   hidden -- re-run the solver's core routines on the hidden fixtures under
             /tests/hidden and validate generalisation.

Exit 0 => checks passed, non-zero => failed.  test.sh writes REWARD=1 only when
both modes pass.
"""
import json
import os
import struct
import sys
from collections import OrderedDict

import numpy as np

sys.path.insert(0, "/app")

TOL_MLP = 0.35
TOL_LOW = 0.5
RANK_MARGIN = 2


# ---------------------------------------------------------------------------
# independent reference generators (recreate the hidden ground truth)
# ---------------------------------------------------------------------------
def mlp_ref(seed, in_dim, hidden):
    rng = np.random.default_rng(seed)
    W = rng.normal(0.0, 1.2, size=(hidden, in_dim))
    W = np.where(np.abs(W) < 0.8, np.sign(W) * (0.8 + 0.5 * np.abs(W)), W)
    b = rng.uniform(-2.0, 2.0, size=(hidden,))
    v = 1.0 + rng.uniform(0.0, 1.4, size=(hidden,))
    return v[:, None] * W, None


def low_ref(seed, m, n, r):
    rg = np.random.default_rng(seed)
    A = rg.normal(0.0, 1.0, (m, r))
    B = rg.normal(0.0, 1.0, (r, n))
    return A @ B


def read_nnt(path):
    raw = open(path, "rb").read()
    if raw[:4] != b"NNT1":
        raise ValueError("bad magic")
    (nt,) = struct.unpack_from("<I", raw, 4)
    off = 8
    out = OrderedDict()
    for _ in range(int(nt)):
        raw[off]; off += 1                       # kind
        nb = raw[off]; off += 1
        name = raw[off:off + nb].decode(); off += nb
        codec = raw[off]; off += 1
        nd = struct.unpack_from("<I", raw, off)[0]; off += 4
        dims = struct.unpack_from("<%dI" % nd, raw, off); off += 4 * nd
        n = struct.unpack_from("<I", raw, off)[0]; off += 4
        if codec == 1:
            sc = struct.unpack_from("<f", raw, off)[0]; off += 4
            q = np.frombuffer(raw[off:off + n], np.int8); off += n
            vals = q.astype(np.float32) * sc
        else:
            vals = np.frombuffer(raw[off:off + 4 * n], np.float32); off += 4 * n
        out[name] = vals.reshape(dims)
    return out


def mlp_rows_match(recovered, ref_rows, tol=TOL_MLP):
    if recovered is None or len(recovered) == 0:
        return False
    rec = np.asarray(recovered, float)
    used = set()
    for rref in ref_rows:
        matched = False
        for ii, r in enumerate(rec):
            if ii in used:
                continue
            if min(np.linalg.norm(r - rref), np.linalg.norm(r + rref)) <= tol:
                matched = True
                used.add(ii)
                break
        if not matched:
            return False
    return True


def lowrank_ok(rec, M, rank_cap):
    rec = np.asarray(rec, float)
    if rec.shape != M.shape:
        return False, "shape mismatch"
    err = np.linalg.norm(rec - M) / np.linalg.norm(M)
    sig = int(np.sum(np.linalg.svd(rec, compute_uv=False) > 1e-6))
    ok = err <= TOL_LOW and sig <= rank_cap + RANK_MARGIN
    return ok, "err=%.3f rank=%d" % (err, sig)


class _ChessNet(object):
    """Placeholder class replacing the accidental module-attribute hack."""
    pass


def _make_chess_net():
    import torch
    import torch.nn as nn

    class Net(nn.Module):
        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(1, 16, 3, padding=1)
            self.conv2 = nn.Conv2d(16, 24, 3, padding=1)
            self.conv3 = nn.Conv2d(24, 32, 3, padding=1)
            self.fc1 = nn.Linear(32, 8)
            self.head = nn.Linear(8, 1)

        def forward(self, x):
            x = torch.relu(self.conv1(x))
            x = torch.relu(self.conv2(x))
            x = torch.relu(self.conv3(x))
            x = x.mean(dim=(2, 3))
            x = torch.relu(self.fc1(x))
            return self.head(x)

    return Net()


# ---------------------------------------------------------------------------
def check_main():
    reports = []
    if not os.path.exists("/app/solve.py"):
        return False, reports
    if not os.path.exists("/app/answer.json"):
        return False, reports
    if not os.path.exists("/app/chess_state.pt"):
        return False, reports
    ans = json.load(open("/app/answer.json"))

    # 1&2) MLP rows
    ref_rows = mlp_ref(20240630, in_dim=6, hidden=6)
    if isinstance(ref_rows, tuple):
        ref_rows = ref_rows[0]
    rec_rows = ans.get("mlp_rows")
    if not mlp_rows_match(rec_rows, ref_rows):
        return False, reports
    nrec = len(rec_rows)
    if not (6 <= nrec <= 9):
        return False, reports
    reports.append("main-mlp ok (%d rows)" % nrec)

    # 3) low-rank
    M = low_ref(11, 40, 40, 3)
    rec = ans.get("lowrank_matrix")
    ok, msg = lowrank_ok(rec, M, 3)
    if not ok:
        return False, reports
    reports.append("main-lowrank ok (%s)" % msg)

    # 4) chess
    import torch
    sd = torch.load("/app/chess_state.pt", map_location="cpu")
    ref_net = read_nnt("/app/chess_net.cnet")
    if set(sd.keys()) != set(ref_net.keys()):
        return False, reports
    for k, tv in ref_net.items():
        a = sd[k].detach().cpu().numpy()
        if not np.allclose(a, tv, atol=1e-6):
            return False, reports
    net = _make_chess_net()
    net.load_state_dict({k: v for k, v in sd.items()})
    out = net(torch.randn(2, 1, 8, 8))
    if not np.all(np.isfinite(out.detach().numpy())):
        return False, reports
    reports.append("main-chess ok")
    return True, reports


# ---------------------------------------------------------------------------
def check_hidden():
    reports = []
    try:
        from solve import extract_mlp, complete_matrix, convert_chessnet
    except Exception as e:
        return False, reports
    H = "/tests/hidden"

    # g1 MLP
    sys.path.insert(0, H + "/g1_mlp")
    import blackbox as hb
    ref = hb._v[:, None] * hb._W
    rows = extract_mlp(hb.query, hb._IN)
    if not mlp_rows_match(rows, ref):
        return False, reports
    if not (8 <= len(rows) <= 11):
        return False, reports
    reports.append("hidden-g1 mlp ok (%d rows)" % len(rows))

    # g2 rank-1
    d2 = json.load(open("%s/g2_rank1/obs.json" % H))
    M2 = low_ref(d2["seed"], d2["m"], d2["n"], d2["rank"])
    ok, msg = lowrank_ok(complete_matrix(d2), M2, d2["rank"])
    if not ok:
        return False, reports
    reports.append("hidden-g2 rank1 ok (%s)" % msg)

    # g3 low / diff size
    d3 = json.load(open("%s/g3_low/obs.json" % H))
    M3 = low_ref(d3["seed"], d3["m"], d3["n"], d3["rank"])
    ok, msg = lowrank_ok(complete_matrix(d3), M3, d3["rank"])
    if not ok:
        return False, reports
    reports.append("hidden-g3 low ok (%s)" % msg)

    # g4 chess
    import torch
    sd4 = convert_chessnet("%s/g4_chess/piece.cnet" % H)
    ref4 = read_nnt("%s/g4_chess/piece.cnet" % H)
    if set(sd4.keys()) != set(ref4.keys()):
        return False, reports
    for k, tv in ref4.items():
        if not np.allclose(sd4[k].detach().numpy(), tv, atol=1e-6):
            return False, reports
    reports.append("hidden-g4 chess ok (%d tensors)" % len(ref4))

    return True, reports


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "main"
    ok, reports = check_main() if mode == "main" else check_hidden()
    for r in reports:
        print("[check][%s] %s" % (mode, r))
    sys.exit(0 if ok else 1)