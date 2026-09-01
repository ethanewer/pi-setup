#!/usr/bin/env python3
import sys, json

OCTET_RE = (r'(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])')


def valid_ip(s):
    if not isinstance(s, str):
        return False
    parts = s.split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdecimal():
            return False
        if p != str(int(p)):          # disallow leading zeros
            return False
        if not (0 <= int(p) <= 255):
            return False
    return True


def collect_target(log_a, log_b, ip):
    seen = {}
    for fp in (log_a, log_b):
        try:
            fh = open(fp)
        except Exception:
            continue
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("ip") != ip:
                continue
            key = (obj.get("ts", ""), obj.get("token", ""))
            seen[key] = key
        fh.close()
    return sorted(seen.keys(), key=lambda k: (k[0], k[1]))


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        sys.stderr.write("usage: respond.py <ip> <logA> <logB> [outfile]\n")
        sys.exit(2)
    ip, log_a, log_b = args[0], args[1], args[2]
    out = args[3] if len(args) > 3 else "/app/incident.json"

    if not valid_ip(ip):
        print("INVALID_IP")
        sys.exit(1)

    recs = collect_target(log_a, log_b, ip)
    report = {
        "target_ip": ip,
        "occurrences": len(recs),
        "tokens": [r[1] for r in recs],
        "start": recs[0][0] if recs else None,
        "end": recs[-1][0] if recs else None,
    }
    with open(out, "w") as f:
        json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()