# PyYAML configuration overlay

Work in the vendored PyYAML source tree at /app/pyyaml. Add a small, safe
configuration-overlay feature that uses PyYAML's public safe-loading and
safe-dumping APIs. The feature must be usable without third-party packages
outside this source tree.

Create /app/pyyaml/lib/yaml/config_overlay.py with this public API:

    DELETE
    load_overlay(stream)
    apply_overlay(base, overlay, *, list_mode="replace")

load_overlay accepts text or a readable stream and parses one YAML document
with safe-construction semantics. It must recognize the scalar tag !delete as
the exported DELETE marker; arbitrary Python/object tags must remain rejected.
The document root must be a mapping.

apply_overlay returns a new mapping and must not mutate either input. Mapping
values are merged recursively when both sides are mappings. A normal overlay
value replaces the base value. A DELETE value removes that key and is valid
only as a mapping value. The list_mode argument accepts exactly:

* replace: use a copied overlay list;
* append: copy the base list followed by the overlay list;
* unique: preserve base order, then append overlay items not already equal to
  an item in the result.

List modes apply at every list-valued merge. A scalar overlay always replaces
the corresponding value; an overlay mapping requires a mapping base at that
key, and an overlay list requires a list base at that key. For a new key,
mapping and sequence subtrees are still traversed: DELETE values remove keys
from new mappings, while a DELETE directly inside a list or tuple is invalid.
The same rule applies to mappings nested inside list or tuple elements. DELETE
cannot be used as a mapping key. Those incompatible mapping/list pairings,
invalid roots, non-mapping bases, unknown list modes, malformed !delete uses,
and cyclic YAML alias/object graphs must raise a clear TypeError or ValueError
rather than silently producing a partial result or leaking DELETE. These
malformed-structure and cycle errors may be reported while loading the YAML
or later while applying the loaded object. Copy nested mappings and sequences
so later caller mutation cannot alter either input.

Also create /app/reproduce_overlay.py, an executable command-line
reproduction. It must accept BASE OVERLAY OUTPUT positional paths and an
optional --list-mode {replace,append,unique}, load both files through the new
module, apply the overlay, and write the result as safe YAML to OUTPUT using
sort_keys=False. Fail with a nonzero status and a concise diagnostic for
invalid input.

Keep the existing PyYAML behavior intact. Do not add network access or depend
on the verifier's tests. The two required deliverables are the module and the
CLI named above; the verifier will import and execute both.
