# jib-stave: repair the jibblin SDK monorepo release line

You inherit a **TypeScript npm-workspaces monorepo** at `/app` for the jibblin
SDK. It has three published packages:

- `@jibblin/core` — token primitives: `Token`, `issue`, `verify`,
  `ageSeconds`, base64url encode/decode, `crc32`.
- `@jibblin/scale` — assessment layer (`assess`, `reify`, `summarize`,
  risk bands) built on `@jibblin/core`.
- `@jibblin/api` — public facade (`Client`, `ClientOptions`, `Claim`) built on
  both.

The repository has full git history; the last commit is a colleague's
unverified "release" work and is the suspected cause of the current state.

**There is no network in this environment.** npm reads everything it needs from
the cache baked into the image (`/root/.npm`). Run npm with `--offline` (for
example `npm ci --offline --no-audit --no-fund`) so it never tries the
registry.

## What the environment contains

- `/app/package.json` — root workspace manifest (`workspaces: ["packages/*"]`).
- `/app/tsconfig.base.json`, `/app/tsconfig.build.json` — shared compiler
  options and the project-references build.
- `/app/packages/core/package.json`,
  `/app/packages/scale/package.json`,
  `/app/packages/api/package.json` — per-package manifests. Each packages to a
  `dist/` build output produced by `tsc -b` with project references.
- `/app/packages/*/src/*.ts` — package sources.
- `/app/packages/*/test/*.ts` — per-package `node --test` suites.
- `/app/package-lock.json` — committed lockfile.
- `/app/consumer/` — downstream smoke fixture. It **compiles against the
  published packages** (through `node_modules` and each package's
  `exports`/`types` entrypoints), exactly like an external user would. Treat it
  as read-only evidence; do not edit it.
- Node.js 22.23.2, npm 10.9.8, and the committed tree are all present.
  `typescript` and `@types/node` are root devDependencies (installed).

The declared deliverables you are responsible for:

- `/app/package.json`
- `/app/packages/core/package.json`
- `/app/packages/scale/package.json`
- `/app/packages/api/package.json`
- `/app/packages/api/dist/index.d.ts` — the declaration file the one build must
  emit for the facade package. The verifier runs that build itself and inspects
  the emitted declarations.

## Symptom report (from the release engineer)

The 2.1.0 release pipeline is red and nobody can cut a new version:

1. A fresh `npm ci` from the committed lockfile **completes** (npm does not
   re-validate workspace metadata against that lockfile), but the installed
   tree then silently disagrees with it: nothing in the pipeline enforces
   agreement, and forcing an install does not make the metadata line up.
2. Once an install is forced, `npm run build -ws` succeeds — the type checker
   is happy — but a downstream project that compiles against the **published**
   packages does **not** see the current API at all. Consumers get
   **1.4-era** declarations: a `Token` that is just a `string`, and
   `mint`/`validate`/`ttl` instead of the current `issue`/`verify`
   /`ageSeconds`/`encodeBase64Url`/`decodeBase64Url`. Code written against the
   documented 2.1.0 API does not type-check.
3. Version metadata is inconsistent: one of the three packages reports a
   different version from the other two, a sibling pins a dependency to that
   stale version, and the installed tree disagrees with the committed
   lockfile. `npm ls @jibblin/core @jibblin/scale` shows the disharmony
   plainly.
4. Running the per-package test suites against the built output fails at
   runtime with "`issue is not a function`"-style errors: the code that runs is
   not the code that was just built.

Everything still resolves at install time (`npm ci --offline` completes):
this is not a broken dependency graph, it is a broken **workspace layout** —
published entrypoints, version metadata, and stale packaged artifacts are
saying one thing while the sources and the build output say another.

## What you must deliver (outcome contract)

Repair the repository so the following acceptance sequence is fully green **on
the intact committed lockfile** (`/app/package-lock.json` must not be
regenerated or edited; the manifests must be made to agree with it):

```
cd /app
npm ci --offline --no-audit --no-fund
npm run build -ws
npm test -ws
./node_modules/.bin/tsc -p consumer/tsconfig.json
```
...plus, at verification time, the same `tsc` against two additional hidden
downstream consumer fixtures that import other parts of the published API.

Concretely the fixed state must satisfy all of:

1. **Install** — `npm ci --offline` succeeds from the committed lockfile and
   the workspace resolves: `npm ls @jibblin/core @jibblin/scale` reports a
   single instance of each, at the release line version.
2. **One build, correct declarations everywhere** — `npm run build -ws` emits
   declaration files for all three packages, and those emitted declarations are
   the ones consumers see: every package's published entrypoints
   (`main`/`types`/`exports`) reference its own build output in `dist/`, and no
   stale packaged artifacts remain in the workspace.
3. **Internal version references resolve** — all three published manifests
   declare version **`2.1.0`**, and each manifest that uses a sibling pins it
   to that line: `@jibblin/scale` depends on `@jibblin/core` via `^2.1.0`,
   `@jibblin/api` depends on both siblings via `^2.1.0`.
4. **Published types are the current API** — every consumer (visible and
   hidden) that imports from `@jibblin/core`, `@jibblin/scale`, or
   `@jibblin/api` must type-check against the *current* 2.1.0 API
   (`Token` records with `kind/subject/issuedAt/nonce/checksum`,
   `issue`/`verify`/`ageSeconds`/`encodeBase64Url`/`decodeBase64Url`,
   `assess`/`reify`/`summarize`, `Client`/`ClientOptions`/`Claim`), with none
   of the 1.4-era surface (`Token` as `string`, `mint`/`validate`/`ttl`,
   `expiresAt`) visible anywhere in the emitted declarations.
5. **Behaviour matches types** — the per-package suites run green against the
   built output (their runtime imports must resolve to the freshly built
   `dist/`, not to stale packaged artifacts).

## Constraints

- Work only inside `/app`. Do not edit `/app/package-lock.json` or
  `/app/consumer/**`. Do not change the public API surface of any package
  (the hidden consumers are written against it).
- The shipped per-package test suites under `packages/*/test/` are part of the
  environment and must be green against the built output; a correct repair
  does not touch them.
- The repository is self-contained and offline; use the baked npm cache.
- You may use git freely (log, diff, show, blame) to understand what the last
  commit changed.

When the acceptance sequence above exits 0 and the declared deliverables are in
place, you are done. The verifier re-runs the whole sequence, compiles the
visible and hidden consumers, and inspects the emitted declaration contents and
manifest metadata exactly as specified above.