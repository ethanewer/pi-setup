# Store layout (README for the fixture, do not modify)

`/app/store` is a miniature content-addressed object store:

```
store/
  refs/HEAD            plain text file whose content is the object ID of the head commit
  objects/<id>.json    one file per object; <id> must equal the SHA-256 hex digest of
                       that object's canonical JSON payload
```

A payload's canonical bytes are `utf-8(json.dumps(obj, sort_keys=True,
separators=(',', ':')))` and its object ID is `sha256(canonical_bytes).hexdigest()`.

Object vocabulary (a small git-like graph):

| type   | JSON |
|--------|------|
| blob   | `{"type": "blob", "text": "..."}` |
| tree   | `{"type": "tree", "blobs": ["<blob-id>", ...]}` |
| commit | `{"type": "commit", "tree": "<tree-id>", "parent": "<commit-id> | null", "message": "..."}` |

For any object, the object file name **must** equal its own SHA-256 digest
(recomputed from the decoded payload bytes). An object whose filename does not
match, or whose file is not valid JSON, is not addressable and is ignored
entirely.