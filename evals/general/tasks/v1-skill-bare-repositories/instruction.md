Create a *bare* Git repository so that teammates can clone it and instantly get a tracked file. Bare repositories have no working tree; they store only version history and refs.

Create the bare repository at `/app/harbor.git`. Then, from a separate ordinary working directory such as `/app/dev`, initialize a normal (non-bare) repository, create the file `README.md` whose contents are exactly the single line:
```
harbor-bare-repository
```
Commit that file, add `/app/harbor.git` as the remote named `origin`, and push the current branch to it. After you finish, cloning `/app/harbor.git` must yield a working copy that contains `README.md` with that exact content.

If needed, configure a Git user name and email (e.g. user.name "Harbor Agent", user.email harbor@example.com) before committing.
