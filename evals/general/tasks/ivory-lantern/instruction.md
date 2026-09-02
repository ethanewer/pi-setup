# ivory-lantern — bake a complete offline mirror for a network-free load

The **Ivory Lantern** field kiosk is deployed at a site with no network: every
artificial-intelligence asset it needs must already be on disk. Its loader,
`/app/load_pretrained.py` (shipped read-only — do not modify it), refuses to
serve unless the **complete** set of pretrained artifacts is present in one
directory: a missing config, weights file, or any tokenizer artifact makes the
offline load fail, which is exactly what a partial mirror produces.

Your job: write the mirror builder, run it to bake a complete mirror from the
scattered upstream source tree, and prove the load works network-free.

## The upstream source tree (read-only)

`/app/upstream/` is a scattered artifact cache. `manifest.json` inside it
lists the logical artifacts that matter:

```json
{
  "manifest_version": 1,
  "case_id": "...",
  "artifacts": [
    {"name": "config", "path": "docs/config.snapshot", "sha256": "..."},
    ...
  ]
}
```

- `path` is relative to the upstream root and may be nested at any depth.
- `sha256` is the hex digest of the source file's exact bytes.
- The tree also contains files **not** listed in the manifest (README notes,
  stale legacy shards). Those are distractors and must **not** be copied into
  the mirror.

## The canonical mirror layout

Each logical artifact must land in the mirror under its canonical filename:

| logical name         | mirrored filename           |
|----------------------|-----------------------------|
| `config`             | `config.json`               |
| `weights`            | `weights.npz`               |
| `vocab`              | `vocab.json`                |
| `merges`             | `merges.txt`                |
| `tokenizer_config`   | `tokenizer_config.json`     |
| `special_tokens_map` | `special_tokens_map.json`   |

A servable mirror is a directory containing **exactly these six files** with
byte content identical to the verified sources.

## Deliverables

1. `/app/build_mirror.py` — runnable as
   ```
   python3 /app/build_mirror.py <upstream_dir> <mirror_dir>
   ```
   It must:
   - read `manifest.json` from `<upstream_dir>`;
   - for every listed artifact: check the source file exists and that its
     sha256 matches the manifest — a missing file or a digest mismatch is a
     hard failure: print a diagnostic to stderr and **exit nonzero**;
   - on failure, **not** leave a complete mirror behind (a leftover partial
     directory is tolerable only if it is missing at least one of the six
     artifacts);
   - on success: copy every artifact's bytes to `<mirror_dir>/<canonical
     filename>`, creating `<mirror_dir>` if needed, overwriting stale files,
     and exit 0.
   It must work on **any** upstream tree following this manifest format (the
   grader runs it, unchanged, on hidden upstream trees) — never hard-code the
   visible paths or digests.

2. `/app/mirror/` — the complete mirror built from `/app/upstream`:
   ```
   python3 /app/build_mirror.py /app/upstream /app/mirror
   ```

3. `/app/offline_check.txt` — the captured output of running the shipped
   loader against your mirror:
   ```
   python3 /app/load_pretrained.py /app/mirror > /app/offline_check.txt
   ```
   It must contain a line starting with `OFFLINE_LOAD_OK`.

## The loader's contract (what "succeeds" means)

`/app/load_pretrained.py` exposes `load_pretrained(assets_dir)` which:
- sets `TRANSFORMERS_OFFLINE=1` and `HF_HUB_OFFLINE=1` (nothing may fetch);
- requires all six artifacts and raises `FileNotFoundError` if any is absent;
- returns a bundle with the parsed `config`, a tokenizer object (`.vocab`,
  `.merges`, `.encode(text)` doing whitespace-split -> vocab id with the
  special `unk_token` fallback), and a `weights` dict whose values are all
  **2-D** float arrays.

When run as a script it prints `OFFLINE_LOAD_OK <dir> ...` on success and
`OFFLINE_LOAD_FAILED: ...` with a nonzero exit on failure.

## Rules

- Do not modify `/app/load_pretrained.py` or anything under `/app/upstream/`.
- Never read anything under `/tests` or `/solution`.
- No network access. Standard library + `numpy` only.

## What the grader does

1. Verifies `/app/mirror` holds exactly the six canonical files, byte-identical
   (sha256) to the manifest-verified sources, and that the loader loads it
   successfully and returns working objects (config fields, 2-D weights,
   tokenizer ids that match an independent reference).
2. Confirms the loader **raises** when one artifact is deleted from a copy of
   the mirror (the complete-mirror property).
3. Re-runs `/app/build_mirror.py` on **hidden upstream trees**: a fresh one
   (must build and load), one with a corrupted source file (digest mismatch —
   must exit nonzero and not leave a complete mirror), and one with a missing
   source file (same).
4. Checks `/app/offline_check.txt` contains `OFFLINE_LOAD_OK`.
