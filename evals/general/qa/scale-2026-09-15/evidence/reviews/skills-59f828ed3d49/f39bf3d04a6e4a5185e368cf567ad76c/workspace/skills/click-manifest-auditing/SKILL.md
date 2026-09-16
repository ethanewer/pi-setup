---
name: click-manifest-auditing
description: Build deterministic Click command-line auditors that validate JSON manifests against a local filesystem and policy without unsafe path traversal.
---

# Click manifest auditing

Use this workflow when a Click CLI must inspect a filesystem from a declarative
manifest and produce machine-readable results.

- Keep invocation state in a small object attached to the root Click context;
  child commands should consume that state instead of reparsing options.
- Use Click's typed `Path` and `File` parameters for user-facing paths, but do
  the security checks yourself: require normalized relative manifest paths,
  reject absolute paths and `..` components, resolve symlinks, and ensure the
  resolved target remains under the selected root.
- Parse JSON with explicit schema checks. Reject duplicate manifest paths,
  malformed hashes, unknown record types, and policy values that cannot be
  enforced. Never silently coerce malformed data into a passing result.
- Separate collection from reporting. Collect stable error records, sort them
  by path and code, and make JSON the canonical output; text output is only a
  presentation of the same result. Hash bytes from the opened file and compare
  both byte count and SHA-256.
- Treat operational failures as a controlled CLI result: diagnostics go to
  stderr, reports go only to the requested destination, and exit status is
  nonzero for malformed input, unsafe paths, policy violations, or mismatches.
  Never overwrite an output path that is also an audited input.

Before finalizing, exercise empty manifests, duplicate and traversal paths,
missing files, symlink escapes, policy limits, malformed JSON, both output
formats, and the stdout/output-file split. Keep the verifier independent of the
implementation and make all ordering deterministic.
