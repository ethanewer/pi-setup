A shared team has created a **bare** Git repository at `/app/team.git`. A bare repository stores only version history and refs — it has no checked-out working files at its top level (no files like `README` visible next to `.git`, and `git rev-parse --is-bare-repository` would report `true`). That makes it suitable as a shared remote that developers push to and clone from.

Demonstrate this workflow:

1. From the pristine working directory, clone the bare repository into a fresh working copy at `/app/developer`:
   `git clone /app/team.git /app/developer`
2. Inside `/app/developer`, if no committed user is set, configure:
   `git config user.email "harbor@example.com"` and `git config user.name "Harbor"`
3. Create `notes.txt` in that working copy whose contents are exactly the single line:
   ```
   team-bare-notes
   ```
4. Stage and commit (subject `add notes`), then push the current branch back to the remote `origin`:
   `git push -u origin <branch>`

After you finish, a fresh clone of `/app/team.git` into a new directory must contain `notes.txt` with the exact content above, proving the commit was pushed into the shared bare remote. Keep `/app/team.git` bare (do not add a working tree there).