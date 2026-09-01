#!/usr/bin/env python3
"""basalt-dial orbital propagator engine (fixed; not a deliverable).

Usage:
  python3 engine.py simulate  <case.json> <config.json> <out.json>
  python3 engine.py reference <case.json> <out.json>

Pure standard library, fully deterministic.
"""
import json
import math
import sys

REFERENCE_METHOD = "rk4"
REFERENCE_STEPS = 4096
MAX_STEPS = 100000
REQUIRED_KEYS = {"method", "steps", "enable_drag", "drag_coeff",
                 "softening", "renormalize"}
METHODS = ("euler", "heun", "rk4")
EVALS_PER_STEP = {"euler": 1, "heun": 2, "rk4": 4}


def err(msg):
    sys.stderr.write("ERR: %s\n" % msg)
    sys.exit(1)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        err("cannot read JSON file %s" % path)


def make_accel(mu, softening, drag, drag_coeff):
    def accel(x, y, vx, vy):
        r2 = x * x + y * y + softening
        r = math.sqrt(r2)
        f = -mu / (r2 * r)
        ax = f * x
        ay = f * y
        if drag:
            ax -= drag_coeff * vx
            ay -= drag_coeff * vy
        return ax, ay
    return accel


def renorm(mu, s, E0):
    """Conserve-energy velocity rescale (changes physics; a tuning trap)."""
    x, y, vx, vy = s
    r = math.sqrt(x * x + y * y)
    v2 = vx * vx + vy * vy
    target = 2.0 * (E0 + mu / r)
    vx, vy = vx * math.sqrt(target / v2), vy * math.sqrt(target / v2)
    return (x, y, vx, vy)


def integrate(mu, s0, T, nsteps, method, softening, drag, drag_coeff,
              renormalize, budget=None):
    accel = make_accel(mu, softening, drag, drag_coeff)
    dt = T / nsteps
    s = tuple(s0)
    nfev = 0
    eps = EVALS_PER_STEP[method]
    if renormalize:
        x, y, vx, vy = s
        r = math.sqrt(x * x + y * y)
        E0 = 0.5 * (vx * vx + vy * vy) - mu / r
    else:
        E0 = None
    for _ in range(nsteps):
        if budget is not None and nfev + eps > budget:
            return None, nfev, "budget-exceeded"
        if method == "euler":
            ax, ay = accel(*s)
            nfev += 1
            s = (s[0] + dt * s[2], s[1] + dt * s[3],
                 s[2] + dt * ax, s[3] + dt * ay)
        elif method == "heun":
            ax1, ay1 = accel(*s)
            k1 = (s[2], s[3], ax1, ay1)
            nfev += 1
            sp = tuple(s[i] + dt * k1[i] for i in range(4))
            ax2, ay2 = accel(*sp)
            nfev += 1
            s = tuple(s[i] + 0.5 * dt * (k1[i] + (sp[2], sp[3], ax2, ay2)[i])
                      for i in range(4))
        else:  # rk4
            ax1, ay1 = accel(*s)
            k1 = (s[2], s[3], ax1, ay1)
            nfev += 1
            s2 = tuple(s[i] + 0.5 * dt * k1[i] for i in range(4))
            ax2, ay2 = accel(*s2)
            k2 = (s2[2], s2[3], ax2, ay2)
            nfev += 1
            s3 = tuple(s[i] + 0.5 * dt * k2[i] for i in range(4))
            ax3, ay3 = accel(*s3)
            k3 = (s3[2], s3[3], ax3, ay3)
            nfev += 1
            s4 = tuple(s[i] + dt * k3[i] for i in range(4))
            ax4, ay4 = accel(*s4)
            k4 = (s4[2], s4[3], ax4, ay4)
            nfev += 1
            s = tuple(s[i] + dt / 6.0 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
                      for i in range(4))
        if renormalize:
            s = renorm(mu, s, E0)
    return list(s), nfev, "ok"


def validate_config(cfg):
    if not isinstance(cfg, dict):
        err("config must be a JSON object")
    if set(cfg.keys()) != REQUIRED_KEYS:
        err("config keys must be exactly %s" % sorted(REQUIRED_KEYS))
    if cfg["method"] not in METHODS:
        err("method must be one of %s" % list(METHODS))
    st = cfg["steps"]
    if not isinstance(st, int) or isinstance(st, bool) or st < 1 or st > MAX_STEPS:
        err("steps must be an integer in [1, %d]" % MAX_STEPS)
    for k in ("enable_drag", "renormalize"):
        if not isinstance(cfg[k], bool):
            err("%s must be a boolean" % k)
    for k in ("drag_coeff", "softening"):
        v = cfg[k]
        if not isinstance(v, (int, float)) or isinstance(v, bool) \
                or not math.isfinite(v):
            err("%s must be a finite number" % k)
    if cfg["softening"] < 0:
        err("softening must be >= 0")
    if not (0.0 <= cfg["drag_coeff"] <= 10.0):
        err("drag_coeff must be in [0, 10]")


def main():
    if len(sys.argv) not in (4, 5):
        err("usage: engine.py simulate <case.json> <config.json> <out.json> "
            "| engine.py reference <case.json> <out.json>")
    mode = sys.argv[1]
    case = load_json(sys.argv[2])
    try:
        mu = float(case["mu"])
        s0 = [float(v) for v in case["state0"]]
        T = float(case["T"])
        name = str(case.get("name", "case"))
        assert len(s0) == 4 and all(math.isfinite(v) for v in s0)
        assert math.isfinite(mu) and mu > 0 and math.isfinite(T) and T > 0
    except Exception:
        err("case.json malformed (need mu>0, T>0, state0 of 4 finite numbers)")

    if mode == "reference":
        final, nfev, status = integrate(mu, s0, T, REFERENCE_STEPS,
                                        REFERENCE_METHOD, 0.0, False, 0.0,
                                        False, budget=None)
        out = {"case": name, "status": status, "nfev": nfev,
               "final": final, "method": REFERENCE_METHOD,
               "steps": REFERENCE_STEPS}
        with open(sys.argv[3], "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=2)
        return

    if mode != "simulate" or len(sys.argv) != 5:
        err("usage: engine.py simulate <case.json> <config.json> <out.json> "
            "| engine.py reference <case.json> <out.json>")
    cfg = load_json(sys.argv[3])
    validate_config(cfg)
    try:
        budget = int(case["budget"])
        tol = float(case["tol"])
        assert budget > 0 and tol > 0
    except Exception:
        err("case.json malformed (need budget>0 and tol>0)")

    final, nfev, status = integrate(mu, s0, T, cfg["steps"], cfg["method"],
                                    float(cfg["softening"]) ** 2,
                                    cfg["enable_drag"],
                                    float(cfg["drag_coeff"]),
                                    cfg["renormalize"], budget=budget)
    if final is not None and not all(math.isfinite(v) for v in final):
        status = "diverged"
        final = None
    out = {"case": name, "status": status, "nfev": nfev, "final": final,
           "method": cfg["method"], "steps": cfg["steps"]}
    with open(sys.argv[4], "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()
