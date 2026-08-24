# diff/merge: three-way merge with git merge-file

A text file was forked: two developers edited their own copies of the same
original. You must **merge** the two edited versions into one file.

## Input files

- `/app/base.txt` — the common ancestor (original) version
- `/app/ours.txt` — one edited version
- `/app/theirs.txt` — another edited version

The two edits touch **different lines**, so the merge is conflict-free.

## Task

1. Use `git merge-file` (a standard three-way merge tool) to merge the three
   versions. For example, run inside `/app`:

   ```
   git merge-file -p ours.txt base.txt theirs.txt
   ```

   `git merge-file` takes three files in the order: current branch, common
   ancestor (base), other branch. `-p` prints the merged result to stdout
   instead of writing to a file.
2. Capture that merged output and write it to **`/app/merged.txt`** (with a
   trailing newline).

The merged file must contain the changes from *both* edited versions: every
line that `ours.txt` changed relative to `base.txt`, and every line that
`theirs.txt` changed relative to `base.txt`. No conflict markers
(`<<<<<<<`, `=======`, `>>>>>>>`) may appear.

The verifier compares `/app/merged.txt` byte-for-byte against the expected
merged content.
