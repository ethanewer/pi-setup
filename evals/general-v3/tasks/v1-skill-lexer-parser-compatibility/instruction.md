# Lexer / parser compatibility

`/app/lexer_rules.json` defines a set of token rules:

```json
{"rules": [ {"name": "<token name>", "pattern": "<regex>"}, ... ]}
```

`/app/input.txt` contains a single line of text with no whitespace.

Determine the token sequence produced by tokenizing the input **left to right** using these rules:

- At each position, try every rule and use the one that matches the **longest** substring starting there; on ties, the rule appearing first in the array wins.
- Advance past that match and repeat; if no rule matches the next character, that is a lexing error (the input is designed so this does not happen).

Write `/app/token_sequence.json` as a JSON array of the matched token **names in order**:

```json
["id", "num", "id"]
```

Implementation hint (Python `re` with `.match` at a given position):

```python
import json, re
rules = json.load(open('/app/lexer_rules.json'))['rules']
src = open('/app/input.txt').read().strip()
names = []
pos = 0
while pos < len(src):
    best = None
    for r in rules:
        m = re.compile(r['pattern']).match(src, pos)
        if m and (best is None or m.end() - pos > best[1]):
            best = (r['name'], m.end() - pos)
    if best is None:
        raise SystemExit('lex error at %d' % pos)
    names.append(best[0])
    pos += best[1]
json.dump(names, open('/app/token_sequence.json', 'w'))
```

Afterward `/app/token_sequence.json` must be valid JSON containing the exact ordered list of token names.