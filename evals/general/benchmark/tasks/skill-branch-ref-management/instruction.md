In `/app/work` there is a git repository whose remote is the bare repository at
`/app/src.git`. The `main` branch has already been pushed to the remote. Running
`git log --oneline` inside `/app/work` shows three commits (oldest first):

- `init repo`
- `add feature X`
- `fix main wiring`

Perform the following **branch/ref management** operations, using normal git commands
within `/app/work`:

1. Create a local branch named `hotfix` whose **tip points at the `add feature X`
   commit** (i.e. the commit whose subject is `add feature X`, found with
   `git log --grep`), so that `hotfix` does *not* include the later `fix main wiring`
   work.
2. Push `hotfix` to the remote (`/app/src.git`) so the remote has a
   `refs/heads/hotfix` referencing that same commit.
3. Create a **lightweight tag** `v1.0` that points at the tip of `hotfix`, and push the
   tag to the remote as `refs/tags/v1.0`.
4. Leave `/app/work` with a clean working tree (`git status --porcelain` prints nothing).

Your result is verified by reading the refs in the remote and the local repository.
