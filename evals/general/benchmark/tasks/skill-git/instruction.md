Create a new Git repository at `/app/repo` and commit a tracked file using Git's core staging/commit workflow.

1. Initialize the repository there (`git init`).
2. If no Git user is configured for this repository, set a local user before committing:
   `git config user.email "harbor@example.com"`
   `git config user.name "Harbor Agent"`
3. Create the file `greeting.txt` in `/app/repo` whose contents are exactly the single line:
   ```
   harbor-git-probe
   ```
4. Stage it with `git add` and commit it with the commit message exactly `add greeting`.
5. Ensure you are on a branch (e.g. `main` or `master`) when you commit — do not use detached HEAD.

The verifier independently checks that `/app/repo` is a valid repository, that the working tree contains `greeting.txt` with the exact content above, and that `git log` shows exactly one commit whose subject is `add greeting`. Do not create additional commits or branches.