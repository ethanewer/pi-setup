# tl-briar-entity: audit and remediate XXE in five XML parsing scripts

The **Briar** ingest pipeline parses untrusted XML with five small Python
scripts. Several of them are exploitable: some resolve external entities from
`file://` URIs (a local file read), and some expand nested general entities
past a documented depth. Your job is to (1) run the analyzer to produce a
per-parser audit, (2) patch every vulnerable parser so the two vulnerability
classes are gone while the documented benign behavior is preserved, and
(3) leave the audit as the honest record of the pre-patch state.

The environment ships in `/app`:

- `/app/parsers/` — five XML parsing scripts (Python 3 stdlib only):
  `snippet_extract.py`, `catalog_fetch.py`, `plain_text.py`,
  `directive_loader.py`, `report_sieve.py`.
- `/app/samples/` — three benign XML files (`sample_a.xml`,
  `sample_b.xml`, `sample_c.xml`) every parser must keep handling.
- `/app/config.json` — the machine-readable contract: entry interface,
  output protocol, extraction rules, `max_entity_depth`, and the two
  canonical vulnerability classes with their exact names.

`/opt/pristine/` holds byte-for-byte copies of the original parsers, the
samples, and `config.json` (read-only reference, never edit it).

## Entry interface and output protocol (all five parsers)

Every parser is invoked as

```
python3 /app/parsers/<name>.py <input.xml>
```

and obeys the protocol in `/app/config.json`:

- **Success**: stdout is exactly `OK ` followed by the document text
  (see extraction rules), no required trailing newline; exit code `0`.
- **Rejection**: exit code non-zero and stdout does not begin with `OK `.

**Extraction rules** (what "the document text" means): concatenate, in
document order, every character-data node's data — text nodes, CDATA
sections, and the character data produced by general-entity expansion.
Comments, processing instructions, the XML declaration, the DOCTYPE /
DTD-subset text, and attribute values are excluded. Character data is only
the content inside the root element: whitespace in the prolog (before the
root element) or epilog (after it) is not character data and is not
extracted; whitespace inside the root element is preserved exactly.
Character references decode to their characters (`&amp;` `&lt;` `&gt;`
`&apos;` `&quot;`, numeric `&#N;` / `&#xH;`), as do entities declared in the
document's DTD internal subset.

## Vulnerability classes (documented in `/app/config.json`)

`max_entity_depth` is **6**. The two classes, used verbatim as audit
`reasons`, are:

1. **`external entity resolution`** — the parser resolves an external
   general entity whose `SYSTEM` system identifier is a `file://` URI, so the
   referenced local file's bytes land in the parsed document text.
2. **`recursive entity expansion`** — the parser expands nested
   general-entity references to a nesting depth greater than 6. A document
   whose DTD declares `e0` and `e_k = "&e_{k-1}&e_{k-1};"` produces a
   contiguous run of 2^k marker characters; a run longer than 64 (2^6)
   characters means expansion went past the documented depth.

## Deliverables

1. `/app/analyze_xxe.py` — the analyzer. It probes every one of the five
   parsers with crafted payloads built in a sandboxed temp directory
   (a `file://` file-read probe pointing at a secret file it writes, and a
   recursive-entity probe), then writes the deterministic audit JSON.
   Interface:
   ```
   python3 /app/analyze_xxe.py [--parsers-dir DIR] [--out FILE] [--max-depth N]
   ```
   defaults `/app/parsers`, `/app/xxe_audit.json`, `6`. It lists the five
   parsers in sorted filename order; each entry is
   `{"parser": <name>, "vulnerable": <bool>, "reasons": [<class names>]}`,
   and the whole document is
   `{"schema": "tl-briar-entity/audit/v1", "max_entity_depth": 6,
   "generated_by": "analyze_xxe.py", "parsers": [...]}`.

2. `/app/xxe_audit.json` — the audit produced by running the analyzer
   **against the original (pre-patch) parsers**. It is the honest record of
   what was exploitable before your fixes; the verifier cross-checks it
   against its own hidden probes, so a hand-written verdict list without real
   analysis will not match. Run the analyzer first (`python3
   /app/analyze_xxe.py`), then patch — do not regenerate the audit after
   patching, or it will describe the fixed state instead of the pre-patch
   one.

3. `/app/parsers/*.py` — the **patched** versions of every parser, written
   in place. The five deliverables are
   `/app/parsers/snippet_extract.py`, `/app/parsers/catalog_fetch.py`,
   `/app/parsers/plain_text.py`, `/app/parsers/directive_loader.py`, and
   `/app/parsers/report_sieve.py`. Every parser flagged `vulnerable` must
   now reject or neutralize both probe classes (for example by refusing
   external entities and rejecting documents whose DTD declares entity
   chains deeper than `max_entity_depth`), while every parser must still
   extract the visible samples and ordinary benign documents exactly per
   the extraction rules. A parser flagged safe (e.g. `report_sieve.py`,
   already defused) can stay as shipped if it already satisfies the
   protocol.

## How the verifier grades

- Re-derives the true pre-patch verdict of each parser from pristine copies
  at `/opt/pristine/parsers` using **hidden** payloads: a `file://` file-read
  probe whose secret lives in `/tests/hidden`, and recursive probes at
  depths 12 and 14 (marker `#`). Your `/app/xxe_audit.json` must match these
  verdicts exactly (vulnerable flag and the exact `reasons` set).
- Runs the patched `/app/parsers/*.py` against the same hidden file-read
  probe, both hidden recursive probes, hidden benign documents
  (`/tests/hidden/benign_*.xml`), and the visible samples: no secret bytes
  may leak, no recursive probe may expand past depth 6 (exit non-zero or a
  marker run of at most 64), and every benign document must come out
  byte-for-byte as the independent reference extractor computes it.
- Re-runs `/app/analyze_xxe.py` against the pristine parsers and requires
  the regenerated audit to be byte-identical to your `/app/xxe_audit.json`
  (proving the audit is a real probe product).
- Requires `/app/config.json` and `/app/samples/*` to be byte-identical to
  the pristine copies.

## Constraints

- Python standard library only (the parsers use `xml.sax` and/or
  `xml.dom.minidom`; `directive_loader.py` reads DTD-subset directives via
  minidom's DOCTYPE). No third-party XML libraries, no network access.
- Everything must be deterministic. Do not delete or rename the five
  parsers, and do not touch anything outside `/app` except `/tmp` scratch.
- The audit JSON must reflect the pre-patch state and be regenerable.