A Git repository exists at `/app/repo` and tracks the file `data.txt` across its history (the last committed content of `data.txt` is the single line `omega`).

Your goal is to package the entire repository into a single-file **bundle** (a portable git transport) and prove it restores correctly.

1. Inside `/app/repo`, create the bundle at `/app/repo.bundle` capturing all refs:
   `git bundle create /app/repo.bundle --all`
2. Confirm the bundle is usable by cloning it to a brand-new directory:
   `git clone /app/repo.bundle /tmp/restore`
3. Confirm `/tmp/restore/data.txt` contains the exact line `omega` (the final committed content).

The verifier independently validates that `/app/repo.bundle` is a valid git bundle file (its header text is `# v2 git bundle`), that it can be cloned, and that the restored `data.txt` equals `omega`.