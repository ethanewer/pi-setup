#!/usr/bin/env python3
"""Extract the financial metrics and their table rows from an HTML report.
Usage: parse_financials.py <input.html> <output.json>

Contract (source of truth):
  * Only the <table id="metrics"> is considered.
  * Row index is 1-based across ALL <tr> elements of that table (the header
    <tr> counts as row 1, spacer/note rows count, too).
  * A metric row is a <tr> that:
      - is NOT a <thead> row (ignoring <th> cells) --
        we only look at <td> cells,
      - has exactly TWO <td> cells,
      - its first <td> is non-empty after stripping whitespace,
      - its second <td> parses as a number after removing commas,
        a leading '$', and surrounding whitespace,
      - the <tr> does NOT carry class "total" (totals must be excluded).
  * Output list sorted by row: [{"metric":..., "amount":<normalized number as
    string>, "row":N}, ...]. amount is the cleaned second-cell text.
"""
import json, re, sys
from bs4 import BeautifulSoup


def clean_number(text):
    t = text.strip().replace(",", "").replace("$", "").strip()
    try:
        float(t)
        return t
    except ValueError:
        return None


def extract(html_path):
    soup = BeautifulSoup(open(html_path, encoding="utf-8").read(), "html.parser")
    table = soup.find("table", id="metrics")
    if table is None:
        return []
    # Every <tr> in the table counts toward the row index, including rows
    # nested inside <thead>/<tbody> (the header <tr> is row 1 per the
    # documented contract). Document order == index order.
    rows = table.find_all("tr")
    out = []
    for idx, tr in enumerate(rows, start=1):
        cls = (tr.get("class") or [])
        if "total" in cls:
            continue
        tds = tr.find_all("td", recursive=False)
        if len(tds) != 2:
            continue
        name = tds[0].get_text(" ", strip=True)
        amount = clean_number(tds[1].get_text(strip=True))
        if not name or amount is None:
            continue
        out.append({"metric": name, "amount": amount, "row": idx})
    out.sort(key=lambda e: e["row"])
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: parse_financials.py <input.html> <output.json>\n")
        sys.exit(2)
    result = extract(sys.argv[1])
    with open(sys.argv[2], "w") as fh:
        json.dump(result, fh, indent=2)
    print("parsed %d metrics" % len(result))
