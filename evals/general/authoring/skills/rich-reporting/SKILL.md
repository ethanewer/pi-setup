---
name: rich-reporting
description: Build deterministic, noninteractive Python reports with Rich logging and console rendering while keeping structured data validation and literal text safe.
---

# Rich reporting

Use this skill when a Python workflow turns structured records into a human-readable report or log stream and needs Rich without allowing input text to become presentation instructions.

## Core workflow

Keep the workflow in three layers:

1. Parse and validate the input into typed, ordinary Python data. Reject malformed records with a concise diagnostic; do not silently coerce missing identity, timestamp, severity, or message fields. Keep validation separate from rendering so the same normalized records drive summaries and output.
2. Compute summaries from the normalized records. State ordering rules explicitly: stable sorting needs a complete key and an original-position tie breaker, while aggregation should preserve a documented first-seen or sorted order. Do not let dictionary/set iteration decide user-visible order.
3. Render only after validation and aggregation. For batch or CI use, configure a `Console` around an explicit text stream with `force_terminal=False`, no color system, a fixed width when wrapping matters, and links disabled. Avoid prompts, live displays, progress spinners, and terminal-size discovery.

## Rich logging decisions

`rich.logging.RichHandler` is a standard-library `logging.Handler`. It formats the record first, then renders a message and a table-like row containing optional time, level, message, and source path. Its default message path constructs `Text(message)`, which treats square brackets as literal text. Markup is opt-in globally or per record through `extra={"markup": True}`; only enable that for trusted, authored presentation strings. For external or user-provided values, keep markup disabled and pass the value as data. A per-record `extra={"highlighter": None}` can suppress the default highlighter when exact text preservation matters.

If a report uses `RichHandler`, attach a formatter whose message field is intentional (often `%(message)s`), set a stable time format or omit time from machine-checked output, and set `enable_link_path=False` when paths must not become terminal hyperlinks. Never depend on ANSI escape sequences as the data contract; test the plain rendered text.

## Structured report safeguards

- Validate the whole top-level shape before producing partial output. Reject wrong JSON types, blank identifiers, invalid timestamps, unsupported levels, and duplicate identifiers when uniqueness is part of the domain. If the workflow promises control-character rejection, define it explicitly and consistently; a robust text policy covers Unicode C0 (`U+0000`–`U+001F`), DEL (`U+007F`), and C1 (`U+0080`–`U+009F`).
- Normalize once, then use the normalized values for both counts and rows. Count every accepted record exactly once and define whether zero-count groups are shown.
- For equal sort keys, retain input order unless the domain specifies a secondary key. Make any truncation, grouping, or case-folding rule visible in the interface rather than inheriting incidental Python behavior.
- Render arbitrary messages as literal text. Do not interpolate untrusted strings into Rich markup, shell commands, format strings, or exception text that is later reparsed. Preserve newlines and bracket characters according to the chosen report contract.
- Make command-line behavior deterministic: explicit UTF-8, no current time, locale, environment-dependent color, filesystem discovery, network access, or interactive input. Return nonzero on invalid input and write diagnostics separately from a valid report.

## Source reference

The implementation details summarized here were checked against Rich commit `9d8f9a372cc5916fd4781fec207ced7ddac2f08f`, especially `docs/source/logging.rst`, `rich/logging.py`, and `rich/_log_render.py`. Rich is MIT-licensed; retain that attribution when redistributing copied source.
