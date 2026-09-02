`/app/repo` is a local Git repository representing a Hugging Face-style **model/data repo** with several revisions. Its history (oldest to newest) contains a file `version.txt` whose tracked contents are:

- commit `v1` (tag `v1`): `alpha`
- commit `v2` (tag `v2`): `beta`
- `HEAD` / working branch (unreleased, newest): `gamma`

Your team wants a reproducible pin to the **`v2` release revision**.

1. Inspect the repository (e.g. `cd /app/repo && git log --oneline --all && git tag`).
2. Check out the pinned release revision so the working tree reflects exactly the `v2` tag:
   `cd /app/repo && git checkout v2`
3. Read the `version.txt` file now in the working tree (`beta`).
4. Write exactly that value (`beta`) to `/app/answer.txt` (no newline required).

The verifier checks out the `v2` tag on the same repo and requires `/app/answer.txt` to equal `beta`.