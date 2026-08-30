# Tiny triple store.

## Storage

`triples.json` is a JSON array of triples. A triple is an ordered array of
exactly three strings: subject, predicate, object.

## Query

`query.txt` holds one graph pattern per line. A pattern is three
whitespace-separated tokens (subject, predicate, object). A token that begins
with `?` is a variable; otherwise it is a constant that must equal the triple
value.

The answer is the set of distinct full variable bindings that satisfy all
patterns simultaneously (a conjunctive join). See `query_result.json` for the
shape the program must produce.