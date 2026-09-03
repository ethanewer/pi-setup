# ds-mistral-manifest — manifest-merge chart engine

This container is a staging box for a small deployment tool. Charts ship in a
self-contained mini format (NOT an upstream package manager): each chart holds
JSON manifest skeletons and a default values table, and your job is to build
the CLI that turns a chart plus values files into rendered manifests with
exact, deterministic merge semantics.

## Shipped files (read them; do not modify)

- `/app/charts/acme-web/chart.json` — the visible chart: `values` defaults +
  a `strategy` table.
- `/app/charts/acme-web/templates/site.json`, `templates/endpoint.json` —
  manifest skeletons with `{{ .path.to.value }}` substitution rules.
- `/app/overrides/prod.json`, `/app/overrides/edge.json` — visible values
  files.

## Deliverables (both required)

1. `/app/render_chart.py` — the CLI, implemented from this document, Python
   3.12 **standard library only** (no third-party packages, no network).
2. `/app/rendered/` — the generated manifests for the visible chart, produced by
   running your CLI exactly once with:

   ```
   cd /app && python3 /app/render_chart.py /app/charts/acme-web \
       --values /app/overrides/prod.json --values /app/overrides/edge.json \
       --out /app/rendered
   ```

## CLI

```
python3 render_chart.py <chart_dir> [--values FILE ...] --out OUT_DIR
```

- `<chart_dir>`: a directory containing `chart.json` and `templates/`.
- `--values FILE`: repeatable. Each file is applied in the exact order given;
  **later layers override earlier ones**. Relative paths resolve against the
  current working directory. Files must be JSON objects.
- `--out OUT_DIR`: required. The renderer creates out_dir if missing, **removes any
  pre-existing contents**, and writes exactly one file per rendered resource.
- Unknown flags or a missing required argument → usage error.

## Values precedence and merge (their #1 job)

Final values are built by deep-merging, in order:

1. `chart.json` → `values` (defaults; optional, treated as `{}` if absent).
2. Each `--values FILE` in CLI order.

Merge rule at every key, per overlay layer:

- overlay value is a JSON `null` → **the key is deleted** from the result
  (deleting an absent key is a no-op).
- base and overlay are **both objects** → recurse (per-key, with null
  deletion inside).
- anything else (scalar, array, mixed types) → the overlay value **replaces**
  the base value. Arrays at the values level are always replaced wholesale;
  there is no array merging at this stage (array policies live in the
  strategy table, below).

## chart.json format

```json
{
  "values": { "...": "default value tree (may be absent)" },
  "strategy": {
    "<template basename>": {
      "<resource path>": {
        "policy": "replace | append | merge-by-key",
        "from": "<values path>",
        "key": "<field path>"        // required only when policy is merge-by-key
      }
    }
  }
}
```

- Strategy keys are template **basenames** (the template filename without the
  `.json` suffix). A strategy key with no matching template file is a chart
  error.
- `from` is a dotted path **into the final values tree** whose value must be a
  JSON array (the *overlay* list). A missing `from` path means an empty
  overlay list.
- The three policies and their exact semantics (applied per resource):

  - `replace` — the resource array at `<resource path>` becomes the overlay
    list (can be `[]`).
  - `append` — the resource array becomes `base + overlay` in that order.
  - `merge-by-key` — base items are merged with matching overlay items. An
    overlay item **matches** a base item when both have the same value at the
    dotted `key` path (e.g. `name` or `metadata.name`). Matching overlay
    items are **deep-merged into the base item** (same null-deletes-a-key
    rule as values merging; arrays inside items are replaced); unmatched
    overlay items are appended at the end, in overlay order. Results keep
    base order; the first base item with a given key value is the merge
    target, and duplicate keys are processed in order.

- If the `<resource path>` does not exist in a rendered resource it is
  created (intermediate objects as needed) and set to the merged result. If
  it exists and is not an array, that is a render error.
- Strategy entries are applied in the order they appear in `chart.json`;
  later entries for the same path operate on the output of earlier ones.
- The engine only ever touches paths declared in the strategy table.

## Templates and substitution

- `templates/` holds `*.json` files (non-`.json` files are ignored); they are
  processed in lexicographic filename order.
- A template document is **one object (one resource)** or an **array of
  objects (multiple resources)** — anything else is a render error.
- A JSON **string value** may be exactly one placeholder:

  ```
  {{ .path.to.value }}
  ```

  (optional whitespace inside the braces; path segments are
  `[A-Za-z0-9_-]+`; the leading dot is required). The placeholder is replaced
  with the **typed JSON value** at that path in the final values — a string,
  number, boolean, null, array, or object are all substituted structurally.
- A path that does not resolve in the final values, or a string that contains
  `{{` / `}}` but is not exactly one placeholder, is a render error.

## Output

- One file per resource. For a single-object template `templates/NAME.json` →
  `OUT_DIR/NAME.json`; for an array template with N resources →
  `OUT_DIR/NAME-<i>.json` where every index `i` (0-based, array order) is
  zero-padded to the number of digits of N (N=3 → `-0.json`..`-2.json`; N=12
  → `-00.json`..`-11.json`).
- Each file holds the resource as **canonical JSON**: keys sorted
  alphabetically at every level, two-space indent, one trailing newline —
  exactly Python's `json.dumps(resource, sort_keys=True, indent=2)` + `"\n"`.
- Nothing else is written; no extra files.

## Exit codes and stderr (must be exact codes and phrases)

| code | meaning | stderr starts with |
|------|---------|--------------------|
| 0    | success | — |
| 2    | CLI usage error | `usage error:` |
| 3    | chart definition error: `chart.json` missing / not an object / malformed JSON; `templates/` missing; strategy references an unknown template; a strategy entry has no `policy`, an unknown `policy` value (not `replace`/`append`/`merge-by-key`), no `from` path, or `merge-by-key` without a `key` | `chart error:` |
| 4    | render error: unreadable/malformed/non-object values file (name it); missing placeholder path; malformed placeholder; `from` value is not a list; merge target at a resource path exists but is not a list; a merge-by-key item lacks its `key` path; template is not an object or array; output I/O failure | `render error:` |

Every failure message must mention the offending file/path/policy name **and**
contain the grader-matched substring so the grader can tell cases apart. The
grader asserts, per failing case, the exact exit code and that stderr contains
exactly one of these substrings — write your messages so they literally contain
them (alongside the offending file/path/policy name):

- chart error (`chart error:` prefix): `chart.json not found` (missing
  `chart.json`); `chart` (malformed or non-object `chart.json`);
  `templates directory not found`; `strategy references unknown template`;
  `has no policy`; `unknown merge policy`; `has no from path`;
  `requires a key field`.
- render error (`render error:` prefix): `values file` (missing,
  unreadable, malformed or non-object values file); `missing value path`;
  `malformed placeholder`; `is not a list` (a non-list `from` value or a
  non-list merge target); `merge target`; `has no key` (a merge-by-key item
  lacking its key path); `must be a JSON object or array` (bad template
  shape).

The grader **recomputes all expected outputs with its own independent merge
engine** and compares exact file sets and canonical JSON bytes — it runs your
CLI on hidden charts with hidden value files (conflicting overrides, null
deletion, merge-by-key with nested conflicts, unknown-policy and other error
cases, empty values) and probes the exit codes above. Hard-coded output for
the visible chart cannot pass the hidden cases.

## Constraints

Python stdlib only; deterministic (no wall-clock, no randomness); no network;
do not read `/tests`; do not modify the shipped files under `/app/charts` or
`/app/overrides`.