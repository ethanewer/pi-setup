#!/bin/bash
# Real oracle for vanta-mesa: write the solve.py client, start the reference
# origin, RUN the client against it to produce /app/answer.json, then stop the
# origin. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"
PORT=20090

# ---- 1. Write the deliverable client (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Fernbrook Nursery catalog client: fetch the offers page and parse it."""
import argparse
import json
import urllib.request
from html.parser import HTMLParser


class OffersParser(HTMLParser):
    """Collects plant articles scoped to <section id="offers">."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = None
        self._in_title = False
        self._title_buf = []
        self.section_depth = 0      # nesting depth of #offers section
        self.depth = 0              # overall tag depth
        self.in_offers = False
        self.articles = []
        self.cur = None
        self.field = None
        self.buf = []

    # -- helpers ------------------------------------------------------
    def _attr(self, attrs, name):
        for k, v in attrs:
            if k == name:
                return v
        return None

    # -- tag handlers ---------------------------------------------------
    def handle_starttag(self, tag, attrs):
        self.depth += 1
        if tag == "title":
            self._in_title = True
            self._title_buf = []
        elif tag == "section":
            sec_id = self._attr(attrs, "id")
            if sec_id == "offers" and not self.in_offers:
                self.in_offers = True
                self.section_depth = self.depth
        elif tag == "article" and self.in_offers:
            cls = self._attr(attrs, "class") or ""
            if "plant" in cls.split():
                self.cur = {"sku": None, "cultivar": None,
                            "price": None, "stock": None}
                self.articles.append(self.cur)
        elif self.cur is not None and self.in_offers:
            cls = (self._attr(attrs, "class") or "").split()
            if tag == "h2" and "cultivar" in cls:
                self.field = "cultivar"
                self.buf = []
            elif tag == "span" and "sku" in cls:
                self.field = "sku"
                self.buf = []
            elif tag == "span" and "price" in cls:
                self.field = "price"
                self.buf = []
            elif tag == "span" and "stock" in cls:
                self.field = "stock"
                self.buf = []

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
            self.title = "".join(self._title_buf).strip()
        elif self.cur is not None and self.field is not None:
            text = "".join(self.buf).strip()
            if self.field == "cultivar":
                self.cur["cultivar"] = text
            elif self.field == "sku":
                self.cur["sku"] = text
            elif self.field == "price":
                self.cur["price"] = self._parse_price(text)
            elif self.field == "stock":
                self.cur["stock"] = self._parse_stock(text)
            self.field = None
            self.buf = []
        elif tag == "article" and self.cur is not None:
            self.cur = None
        elif tag == "section" and self.in_offers and self.depth == self.section_depth:
            self.in_offers = False
        self.depth -= 1

    def handle_data(self, data):
        if self._in_title:
            self._title_buf.append(data)
        if self.cur is not None and self.field is not None:
            self.buf.append(data)

    # -- field parsers ----------------------------------------------------
    @staticmethod
    def _parse_price(text):
        text = text.strip()
        if text.startswith("$"):
            text = text[1:].strip()
        if not text:
            return None
        return float(text)

    @staticmethod
    def _parse_stock(text):
        text = text.strip()
        if text.lower() == "sold out":
            return 0
        prefix = "In stock:"
        if text.startswith(prefix):
            text = text[len(prefix):].strip()
        try:
            return int(text)
        except ValueError:
            return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--origin", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    url = args.origin.rstrip("/") + "/"
    with urllib.request.urlopen(url, timeout=30) as resp:
        html = resp.read().decode("utf-8")

    p = OffersParser()
    p.feed(html)
    p.close()

    report = {"title": p.title or "",
              "plants": [{"sku": a["sku"], "cultivar": a["cultivar"],
                          "price": a["price"], "stock": a["stock"]}
                         for a in p.articles]}
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print("wrote %s (%d plants)" % (args.out, len(report["plants"])))


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Start the reference origin and run the client against it.
python3 /app/origin.py /app/ref_config.json "$PORT" &
ORIGIN_PID=$!
for _ in $(seq 1 50); do
    if python3 -c 'import urllib.request,sys
try:
    urllib.request.urlopen("http://127.0.0.1:'$PORT'/", timeout=0.5).read()
    sys.exit(0)
except Exception:
    sys.exit(1)' 2>/dev/null; then
        break
    fi
    sleep 0.2
done

python3 "$SOLVER" --origin "http://127.0.0.1:$PORT" --out "$OUT"
RC=$?

kill "$ORIGIN_PID" 2>/dev/null || true
wait "$ORIGIN_PID" 2>/dev/null || true

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
exit "$RC"
