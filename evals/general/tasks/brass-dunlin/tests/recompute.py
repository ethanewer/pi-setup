"""Independent recomputation + canonicalization for brass-dunlin's verifier.

Deliberately written separately from the agent-facing program so the visible
case is checked against a from-scratch recomputation of the documented
semantics.
"""
import json
import re

ISO_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$"
)
LINE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z device=(\S+) "
    r"metric=([A-Za-z0-9_]+) value=(-?\d+(?:\.\d+)?)$"
)


def _num(x):
    if isinstance(x, bool):
        return None
    return x if isinstance(x, (int, float)) else None


def recompute(rules_path, log_paths):
    """Return (alerts, events, statistics) per the documented semantics."""
    try:
        with open(rules_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = None
    rules = []
    if isinstance(data, dict) and isinstance(data.get("rules"), list):
        for r in data["rules"]:
            if not isinstance(r, dict):
                continue
            rid = r.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            rules.append({
                "id": rid,
                "metric": r["metric"] if isinstance(r.get("metric"), str) else None,
                "max": _num(r.get("max")),
                "threshold": r["threshold"]
                if isinstance(r.get("threshold"), int)
                and not isinstance(r.get("threshold"), bool) else 0,
                "severity": r["severity"]
                if isinstance(r.get("severity"), str) else "info",
            })

    counts = [0] * len(rules)
    ipsets = [set() for _ in rules]
    events = []
    for lp in log_paths:
        try:
            fh = open(lp, encoding="utf-8")
        except OSError:
            continue
        with fh:
            for raw in fh:
                m = LINE.match(raw.rstrip("\n"))
                if not m:
                    continue
                dev, met, val = m.group(1), m.group(2), float(m.group(3))
                for i, r in enumerate(rules):
                    if r["metric"] == met and r["max"] is not None and val > r["max"]:
                        counts[i] += 1
                        ipsets[i].add(dev)
                        events.append({"rule": r["id"], "device": dev,
                                       "value": val, "line": raw.rstrip("\n")})

    alerts = [(r["id"], r["severity"], counts[i], sorted(ipsets[i]))
              for i, r in enumerate(rules) if counts[i] >= r["threshold"]]
    statistics = {}
    for i, r in enumerate(rules):
        statistics[r["id"]] = (
            r["id"], r["metric"],
            None if r["max"] is None else round(float(r["max"]), 6),
            r["threshold"], r["severity"], counts[i],
            len(ipsets[i]), sorted(ipsets[i]),
        )
    return alerts, events, statistics


def canon_alert(obj):
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"timestamp", "alerts"}, set(obj.keys())
    assert isinstance(obj["timestamp"], str) and ISO_RE.match(obj["timestamp"]), \
        "bad timestamp %r" % (obj["timestamp"],)
    out = []
    for al in obj["alerts"]:
        assert isinstance(al, dict), al
        assert set(al.keys()) == {"id", "severity", "matches", "ips"}, set(al.keys())
        out.append((al["id"], al["severity"], int(al["matches"]), list(al["ips"])))
    return out


def canon_report(obj):
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"timestamp", "events", "statistics"}, set(obj.keys())
    assert isinstance(obj["timestamp"], str) and ISO_RE.match(obj["timestamp"]), \
        "bad timestamp %r" % (obj["timestamp"],)
    events = []
    for e in obj["events"]:
        assert isinstance(e, dict), e
        assert set(e.keys()) == {"rule", "device", "value", "line"}, set(e.keys())
        events.append((e["rule"], e["device"], round(float(e["value"]), 6), e["line"]))
    stats = {}
    for rid, s in obj["statistics"].items():
        assert isinstance(s, dict), s
        assert set(s.keys()) == {"id", "metric", "max", "threshold", "severity",
                                 "matches", "unique_ips", "ips"}, set(s.keys())
        mx = None if s["max"] is None else round(float(s["max"]), 6)
        stats[rid] = (s["id"], s["metric"], mx, int(s["threshold"]),
                      s["severity"], int(s["matches"]),
                      int(s["unique_ips"]), list(s["ips"]))
    return (events, stats)
