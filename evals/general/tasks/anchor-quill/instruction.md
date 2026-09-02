# Larkspur Labs — declare the mailing lists in the canonical config

You are the mail operator for **Larkspur Labs**. The lab's mail hub runs
Postfix locally in this container. Every mailing list of the lab **must** be
declared in the **canonical virtual-alias map at the fixed path
`/etc/postfix/virtual`**. Config placed at any other path is not honored by
the hub and the lists will not function — the grader inspects only the
canonical path.

Postfix is already installed. As is usual on a container there is no mail
daemon supervision; the hub's *configuration files* are what matter here (the
map file, the rebuilt `.db` map, and `main.cf`).

## Deliverable (required)

`/app/apply_lists.py` — a runnable Python 3 program with this interface:

```
python3 /app/apply_lists.py <spec_file>
```

It reads a list-spec file (format below) and applies it to the canonical
Postfix configuration. It will be executed by the grader on the provided
spec **and on hidden spec files**, so it must implement the documented
contract, not just the visible values.

## List-spec format (`<spec_file>`)

Plain text, one list per line:

- Blank lines are ignored.
- Lines whose first non-blank character is `#` are comments and are ignored.
- Every other line is whitespace-separated tokens: the **first token is the
  list address** (it must contain `@`) and the **remaining tokens are its
  delivery destinations** (at least one required).
- A line that violates the above (no `@` in the first token, no destinations,
  or an empty line with only spaces) is **malformed**: skip it silently and
  continue; the program must still apply the valid lists and exit 0.

## What applying a spec means (do exactly this, idempotently)

1. Rewrite the canonical map `/etc/postfix/virtual` so it contains **exactly
   one entry per valid list in the spec** and nothing else (no leftovers from
   previous runs — applying a spec replaces the whole map):
   ```
   <list-address> <dest1>,<dest2>,<dest3>
   ```
   Destinations are comma-separated with no spaces; entries may be in any
   order; a trailing newline is fine. Comment lines are allowed but not
   required.
2. Ensure `virtual_alias_maps` is declared in `/etc/postfix/main.cf` and
   references the canonical file, e.g.:
   ```
   virtual_alias_maps = hash:/etc/postfix/virtual
   ```
   (using `postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"` is
   acceptable and idempotent).
3. Rebuild the map database so Postfix actually honors it: run
   `postmap /etc/postfix/virtual` (producing `/etc/postfix/virtual.db`).

The program must be **idempotent**: applying the same spec twice leaves the
same state. It must exit non-zero only if the spec file cannot be read; a
spec that is empty or all-comments is valid and results in an empty map
(file rewritten empty, `.db` rebuilt).

## Provided fixture

`/app/fixtures/lists.spec` — the lab's current list spec. Apply it once
yourself so the hub's canonical configuration is live:

```
python3 /app/apply_lists.py /app/fixtures/lists.spec
```

## Edge cases the grader probes on hidden specs

- Specs with several lists and multi-destination lists.
- A single-list, single-destination spec.
- Specs with comments, blank lines, and malformed lines (missing
  destinations, addresses without `@`) that must be skipped.
- An empty (all-comments) spec: the canonical map must end up empty with the
  `.db` rebuilt.

## Constraints

- The grader runs `/app/apply_lists.py` unchanged on hidden specs.
- Do not modify the provided `/app/fixtures/lists.spec`.
- The canonical map must live at `/etc/postfix/virtual` — no other path is
  inspected or honored.
- Standard library only; using the installed `postmap`/`postconf` binaries is
  expected.
