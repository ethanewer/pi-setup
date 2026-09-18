# Repository instructions

## Package commands

This repository has no root `package.json`. Do not run `npm`, `npx`, or package build commands from the repository root.

Run package commands from the package that owns the changed source. For example, after changing `forks/pi-dynamic-workflows-safe/src/`, run:

```sh
cd forks/pi-dynamic-workflows-safe
npm run build
```

Commit the generated `dist/` changes with their source changes, then run `git diff --check` from the repository root.
