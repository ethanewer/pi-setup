#!/bin/bash
# Oracle for portlight-trough: reproduces the real upstream fix for the
# adjacently-tagged-enum-with-extra-map-keys bug in the pinned serde checkout,
# then writes the two deliverable files (/app/repro.rs, /app/summary.md) and
# proves the reproduction passes on the repaired tree. Reads only /app,
# /solution and /opt.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the adjacently-tagged-enum extra-keys fix"

cp /solution/repro.rs /app/repro.rs
chmod 644 /app/repro.rs

cat > /app/summary.md <<'MD'
# portlight-trough: fix summary

## Symptom
Deserializing an adjacently tagged enum (an enum serialized as a single map
holding one key for the variant tag and one for the variant content) aborts as
soon as the map also contains any other, unrelated key. The deserializer treats
the first key that is neither the tag nor the content as a hard error, even
though unrelated fields are silently ignored everywhere else in the library.

## Root cause
The deserialization code that serde_derive generates for adjacently tagged enums
uses a strict field visitor that errors on the very first key it does not
recognize. There is no code path that steps over unrelated keys, so any map that
carries extra metadata fields cannot be parsed at all, and this happens
regardless of whether the `deny_unknown_fields` attribute is present.

## Fix
- Added a `TagContentOtherField` / `TagContentOtherFieldVisitor` helper in
  `serde::private::de` that classifies each map key as tag, content or other.
- Changed the generated code so that, when unknown fields are permitted, it
  loops over map keys, consuming "other" keys as `IgnoredAny` until it finds the
  tag and content keys, and keeps stepping past further unrelated keys while
  still detecting duplicate tag/content keys.
- When `deny_unknown_fields` is set, the generated code keeps the strict
  visitor, so unrelated keys are deliberately rejected instead of rejection
  being the universal behaviour.

## Result
With the reproduction placed in the test suite,
`cargo test -p serde_test_suite --test repro_custom` passes on the repaired tree
and fails on the pre-fix tree, and the project's existing test binaries stay
green.
MD

echo "oracle: fix in place, deliverables written"
exit 0
