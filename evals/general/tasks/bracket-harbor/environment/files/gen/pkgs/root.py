# Root files: module manifest, project docs, ignore rules.

GO_MOD = """\
module bh

go 1.22
"""

README = """\
# bh: a small query engine

`bh` is a self-contained query engine for flat, fixed-schema event stores. It
parses a small SQL-like predicate language, canonicalizes field references,
and evaluates conditions against in-memory rows.

## Repository map

    cmd/bh                 command-line front-end (banner, canon, select)
    internal/version       build identity, feature flags
    internal/token         token kinds, reserved words, operator tiers,
                           canonical field keys
    internal/lexer         source -> token stream
    internal/ast           condition/query tree and canonical formatter
    internal/parser        precedence-climbing parser (conditions + SELECT)
    internal/schema        column type registry and coercion
    internal/store         fixed-schema in-memory row store
    internal/idx           canonical-key inverted indexes and planner hints
    internal/query         normalization, evaluation, selection
    internal/report        aligned table / csv rendering with totals
    internal/conf          sectioned key=value configuration loader

## The language

A condition is built from boolean operators (`AND`, `OR`), comparisons
(`=`, `!=`, `<`, `<=`, `>`, `>=`), membership (`IN (...)`), pattern tests
(`LIKE`, `NOT LIKE`), range tests (`BETWEEN ... AND ...`), null tests
(`IS NULL`, `IS NOT NULL`) and parentheses. Field names are case-insensitive
and whitespace-tolerant when compared: every consumer routes them through
`token.CanonKey` first.

The operator precedence ladder is owned by package `token`; see
`internal/token/op.go` for the documented contract.

```
bh version
bh canon "p = 1 OR q = 2"
bh select "SELECT * FROM probe WHERE a = 1"
```

## Development

    go build ./...
    go vet ./...
    go test ./...

The repository is Go 1.22, stdlib only, no external dependencies.
"""

GITIGNORE = """\
/bh
/bin/
*.test
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "go.mod": ("base", _f(GO_MOD)),
    "README.md": ("base", _f(README)),
    ".gitignore": ("base", _f(GITIGNORE)),
}