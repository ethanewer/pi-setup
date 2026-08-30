#!/bin/bash
# drift-mantle oracle. Writes the real /app/solve.py (a fully general program)
# and runs it on the visible fixture, producing every deliverable at literal
# /app paths. Never reads the verifier tree.
set -eu

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""drift-mantle oracle: access-log IP census and report builder.

CLI: python3 solve.py <log> <out_dir>
Reads one text access log and extracts strictly-valid IPv4 addresses (each
octet 0..255, no leading zeros, and not part of a longer alphanumeric token),
then writes five deliverables into OUT_DIR: report.txt, result.txt,
result.csv, value.txt and out.jpg.
"""
import csv
import os
import re
import sys

# strict octet fragment (competency C-5c7fbe9f)
OCTET = r"(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
V4 = re.compile(
    r"(?<![0-9A-Za-z])"
    + OCTET + r"\." + OCTET + r"\." + OCTET + r"\." + OCTET
    + r"(?![0-9A-Za-z])"
)
# permissive dotted tokenizer used only for FLAG classification
PERM = re.compile(
    r"(?<![0-9A-Za-z])([0-9]{1,3}(?:\.[0-9]{1,3}){3})(?![0-9A-Za-z])"
)

JPG_W, JPG_H = 640, 480


def parse_log(path):
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8", "replace")
    total_lines = text.count("\n")
    if text and not text.endswith("\n"):
        total_lines += 1

    flag = "PRISTINE"
    for tok in PERM.findall(text):
        if any(int(t) > 255 for t in tok.split(".")):
            flag = "OUT_OF_RANGE"
            break
    if flag == "PRISTINE":
        for tok in PERM.findall(text):
            if any(len(t) >= 2 and t[0] == "0" for t in tok.split(".")):
                flag = "LEADING_ZERO"
                break

    cnt = {}
    for ip in V4.findall(text):
        cnt[ip] = cnt.get(ip, 0) + 1

    ordered = sorted(cnt.keys(), key=lambda i: (-cnt[i], i))
    rows = []
    for ip in ordered:
        o = [int(x) for x in ip.split(".")]
        rows.append({"ip": ip, "count": cnt[ip], "risk": (sum(o) % 10)})
    total_hits = sum(cnt.values())
    return {
        "basename": os.path.basename(path),
        "flag": flag,
        "rows": rows,
        "total_lines": total_lines,
        "total_hits": total_hits,
        "distinct": len(rows),
        "busiest": rows[0] if rows else None,
    }


def render_report(s):
    b = s["busiest"]
    if b:
        obj, res = b["ip"], "%s:%d:%d" % (b["ip"], b["count"], b["risk"])
    else:
        obj, res = "-", "-"
    verdict = "GO" if (s["distinct"] >= 2 and s["total_hits"] >= 5) else "NO-GO"
    header = "%4s  %-12s  %5s  %4s" % ("#", "IP", "HITS", "RISK")
    out = [
        "FILE: %s" % s["basename"],
        "LINES: %d" % s["total_lines"],
        "IPS: %d" % s["distinct"],
        "HITS: %d" % s["total_hits"],
        "FLAG: %s" % s["flag"],
        "VERDICT: %s" % verdict,
        "OBJ: %s" % obj,
        "RESULT: %s" % res,
        "",
        header,
    ]
    for i, r in enumerate(s["rows"][:10], 1):
        out.append("%4d  %-12s  %5d  %4d"
                   % (i, r["ip"], r["count"], r["risk"]))
    return "\n".join(out) + "\n", verdict, res


def make_jpg(s, path):
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (JPG_W, JPG_H), (250, 250, 250))
    d = ImageDraw.Draw(img)
    top = s["rows"][:10]
    if top:
        maxc = max(r["count"] for r in top) or 1
        bw = (JPG_W - 80) / len(top)
        for i, r in enumerate(top):
            hgt = int(220 * r["count"] / maxc)
            x0 = 40 + i * bw
            d.rectangle([x0, 300 - hgt, x0 + max(4, bw * 0.8), 300],
                        fill=(0, 90, 160))
    img.save(path, "JPEG", quality=85)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: solve.py <log> <out_dir>")
    log, out = sys.argv[1], sys.argv[2]
    if not os.path.isfile(log):
        sys.exit("no such log file: %s" % log)
    os.makedirs(out, exist_ok=True)
    s = parse_log(log)
    base = s["basename"]

    # value.txt: only the float-parseable total hit count
    with open(os.path.join(out, "value.txt"), "w") as f:
        f.write("%d\n" % s["total_hits"])

    # result.csv: exact column set/order, string rows
    with open(os.path.join(out, "result.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["ip", "count", "risk"])
        for r in s["rows"]:
            w.writerow([r["ip"], str(r["count"]), str(r["risk"])])

    # result.txt: label-per-line
    with open(os.path.join(out, "result.txt"), "w") as f:
        for r in s["rows"]:
            f.write("%s name=%s count=%d risk=%d\n"
                    % (r["ip"], base, r["count"], r["risk"]))

    # report.txt
    report, _, _ = render_report(s)
    with open(os.path.join(out, "report.txt"), "w") as f:
        f.write(report)

    # out.jpg
    make_jpg(s, os.path.join(out, "out.jpg"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod +x /app/solve.py

python3 /app/solve.py /app/access.log /app

# Assert every declared deliverable was actually created at its literal /app
# path by running the solver on the visible fixture /app/access.log.
for f in /app/report.txt /app/out.jpg /app/result.csv /app/result.txt \
         /app/value.txt; do
  [ -f "$f" ] || { echo "oracle: missing deliverable $f" >&2; exit 1; }
done