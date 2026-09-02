# Release archive audit toolkit

The release team needs one auditable pipeline over a gzipped tar archive.
Write `/app/solve.py`, then run it on the visible inputs:

```
python3 /app/solve.py /app/release.tar.gz /app/config.json /app/out
```

Do not modify `/app/release.tar.gz` or `/app/config.json`. Your program will
be run on unseen archives and configs with the same contract, so it must be
fully general. All output goes under the output directory (third argument).

## Config keys

- `target_pattern` — substring; the first non-directory archive member (in
  archive listing order) whose name contains it is the target entry.
- `prune_patterns` — list of substrings; members whose name contains any
  pattern are excluded from the mirror.
- `salt`, `iterations` — PBKDF2 parameters for the hash map.
- `src_prefix`, `dst_prefix`, `paths` — relocation table input.
- `acl_group` — POSIX group for the shared directory ACLs.

## Required behavior

For the visible run (output directory `/app/out`) this means the answer file
is `/app/out/answer.json`. In general:

1. **Targeted extraction.** Extract the bytes of the target entry to
   `OUT/extracted.bin` (raw file content only).
2. **Pruned mirror.** Extract the archive into `OUT/mirror/` skipping pruned
   members, keeping the archive's internal top-level directory (`pkg`).
   Symbolic links (including dangling ones) must be preserved as symlinks,
   not materialized. The source archive must remain byte-identical.
3. **ISO9660 image.** Embed the mirrored toolchain directory
   (`OUT/mirror/pkg/toolchain`) into `OUT/release.iso` using `genisoimage`
   non-interactively. The image must list the toolchain files under
   `isoinfo -l`.
4. **Shared directory ACLs.** Create `OUT/shared/` and apply POSIX ACLs for
   `acl_group`: live read+execute access on the directory itself AND default
   ACLs so that children created later inherit the same group access. Use
   `setfacl`; the container has the `acl` tools installed.
5. **PBKDF2 hash map.** For every regular (non-symlink) file in the mirrored
   tree under `OUT/mirror/pkg`, compute
   `pbkdf2_hmac('sha256', file_bytes, salt.encode(), iterations)` hex, keyed
   by path relative to `OUT/mirror/pkg`.
6. **Relocation table.** For each path in `paths`, rewrite the configured
   `src_prefix` to `dst_prefix` using exact path-prefix semantics on
   components: `/srv/build/x` matches prefix `/srv/build`, but `/srv/buildpkg`
   does not; a path equal to the prefix (with or without a trailing slash)
   maps to `dst_prefix` exactly; non-matching paths pass through unchanged.

## `OUT/answer.json` (exact keys)

```json
{
  "extracted": "<target member name as listed in the archive>",
  "symlinks_preserved": <int>,
  "file_count": <int, number of hashed regular files>,
  "hashes": {"<relpath>": "<pbkdf2 hex>", ...},
  "relocations": {"<input path>": "<relocated path>", ...},
  "iso_size": <int, size of OUT/release.iso in bytes>,
  "acl": {"group": "<acl_group>", "shared_dir": "OUT/shared"}
}
```

(`OUT/shared` means the literal shared-directory path you created.)

## Edge cases the checker probes

- hidden archives with different nesting, targets, prune patterns, salts,
  and iteration counts;
- prefix decoys (`/a/data2` vs prefix `/a/data`, truncated prefixes,
  trailing slashes);
- symlink preservation counts, including dangling links;
- ACL inheritance verified by creating a fresh child after your run;
- source archive bytes must be unchanged after your pipeline runs.
