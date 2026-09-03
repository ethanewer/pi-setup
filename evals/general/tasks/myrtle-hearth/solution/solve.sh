#!/bin/bash
# Oracle for myrtle-hearth: author the ordered sound-change derivation
# engine deliverable and run it on the visible fixtures to produce the
# derived lexicon. Pure stdlib reference implementation of the documented
# semantics. Never reads /tests.
set -eu

cat > /app/derive.py <<'PYEOF'
#!/usr/bin/env python3
"""myrtle-hearth: ordered sound-change derivation engine.

Usage: python3 derive.py <rules.json> <lexicon.txt> <out.tsv>

Applies the changes in rules.json strictly in list order to every word in
lexicon.txt and writes one `input<TAB>derived` line per word to out.tsv.
"""
import json
import sys

EDGE = "#"
NIL = "0"
USAGE = "usage: python3 derive.py <rules.json> <lexicon.txt> <out.tsv>"


def left_ok(word, i, left):
    """Does `left` constrain segment position i of word?"""
    if left == EDGE:
        return i == 0
    if left == "":
        return True
    return i >= 1 and word[i - 1] == left


def right_ok(word, i, right):
    if right == EDGE:
        return i == len(word) - 1
    if right == "":
        return True
    return i + 1 < len(word) and word[i + 1] == right


def before_ok(word, b, left):
    """`left` constraint for insertion boundary b (word[b-1] is before)."""
    if left == EDGE:
        return b == 0
    if left == "":
        return False
    return b >= 1 and word[b - 1] == left


def after_ok(word, b, right):
    """`right` constraint for insertion boundary b (word[b] is after)."""
    if right == EDGE:
        return b == len(word)
    if right == "":
        return False
    return b < len(word) and word[b] == right


def apply_change(word, change):
    """One rule: single pass over pre-pass matches, rightmost applied first."""
    target = change["target"]
    result = change["result"]
    left = change.get("left", "")
    right = change.get("right", "")
    if target == NIL:
        matches = [b for b in range(len(word) + 1)
                   if before_ok(word, b, left) and after_ok(word, b, right)]
        for b in reversed(matches):
            word.insert(b, result)
        return word
    matches = [i for i in range(len(word))
               if word[i] == target
               and left_ok(word, i, left) and right_ok(word, i, right)]
    if result == NIL:
        for i in reversed(matches):
            del word[i]
    else:
        for i in reversed(matches):
            word[i] = result
    return word


def load_changes(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict) or not isinstance(data.get("changes"), list):
        raise ValueError('rules.json must be an object with a "changes" list')
    for change in data["changes"]:
        if not isinstance(change, dict) or "target" not in change or "result" not in change:
            raise ValueError('each change needs "target" and "result"')
        target, result = change["target"], change["result"]
        left = change.get("left", "")
        right = change.get("right", "")
        if not all(isinstance(v, str) for v in (target, result, left, right)):
            raise ValueError("change fields must be strings")
        if target == EDGE or result == EDGE:
            raise ValueError('target/result cannot be "#"')
        if target == NIL and result == NIL:
            raise ValueError("an insertion rule needs a real result segment")
    return data["changes"]


def main(argv):
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    rules_path, lexicon_path, out_path = argv
    try:
        changes = load_changes(rules_path)
    except (OSError, ValueError) as exc:
        print("derive.py: rules error: %s" % exc, file=sys.stderr)
        return 1
    try:
        with open(lexicon_path, "r", encoding="utf-8") as fh:
            raw_lines = fh.read().splitlines()
    except OSError as exc:
        print("derive.py: lexicon error: %s" % exc, file=sys.stderr)
        return 1
    rows = []
    for raw in raw_lines:
        line = raw.strip()
        if not line or line.startswith(EDGE):
            continue
        tokens = line.split()
        for token in tokens:
            if token == EDGE or token == NIL:
                print("derive.py: reserved token %r in lexicon word" % token,
                      file=sys.stderr)
                return 1
        word = list(tokens)
        for change in changes:
            word = apply_change(word, change)
        rows.append(line + "\t" + " ".join(word))
    text = "\n".join(rows) + ("\n" if rows else "")
    try:
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(text)
    except OSError as exc:
        print("derive.py: cannot write %s: %s" % (out_path, exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PYEOF

python3 /app/derive.py /app/rules.json /app/lexicon.txt /app/derived.tsv

echo "solve.sh done"
cat /app/derived.tsv