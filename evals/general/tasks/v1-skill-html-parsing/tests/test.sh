#!/bin/bash
reward=0
mkdir -p /logs/verifier
if [ -f /app/items.json ]; then
  if python3 - <<'PYEOF'
import json
from html.parser import HTMLParser

class TableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_table = False
        self.cell = None
        self.buf = ''
        self.rows = []
        self.row = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'table' and attrs.get('id') == 'items':
            self.in_table = True
        elif self.in_table and tag in ('th', 'td'):
            self.cell = tag
            self.buf = ''
        elif self.in_table and tag == 'tr':
            self.row = []
    def handle_data(self, data):
        if self.in_table and self.cell is not None:
            self.buf += data
    def handle_endtag(self, tag):
        if self.in_table and tag in ('th', 'td') and self.cell == tag:
            self.row.append(self.buf.strip())
            self.cell = None
            self.buf = ''
        elif self.in_table and tag == 'tr' and self.row:
            self.rows.append(self.row)
            self.row = []

p = TableParser()
p.feed(open('/app/page.html').read())
table = [r for r in p.rows if r]
data_rows = table[1:]
exp = [{'name': r[0], 'qty': int(r[1]), 'price': float(r[2])} for r in data_rows]
got = json.load(open('/app/items.json'))
assert got == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt