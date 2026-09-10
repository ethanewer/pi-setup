# stanchion-compass: split a bloated frontend build

`/app` is **stanchion-compass**, a working React single-page application
(Vite 7 + React 19, TypeScript sources, no build errors). It is a small
internal analytics console with four routes selected through the URL hash:

| route      | view                     | what it renders                                          |
| ---------- | ------------------------ | ------------------------------------------------------- |
| `#/`       | home                     | landing page with navigation links                       |
| `#/charts` | `src/views/ChartsView`   | a station time-series table (heavy generated data)      |
| `#/reports`| `src/views/ReportsView`  | a report-template catalogue (heavy generated data)     |
| `#/admin`  | `src/views/AdminView`    | an audit-index browser (heavy generated data)           |

The app works: `npm run build` succeeds and every route renders. The problem
is its **initial JavaScript payload**, which is enormous: the three heavy
views and their data modules are all bundled into the single entry chunk, so
a first-time visitor downloads roughly a megabyte of JavaScript before
anything renders, even if they only ever open the home page.

Your job is to fix the build so that the application keeps working but the
**initial fetch** fits under the byte budget below.

## Environment

- Node.js 22 and npm are installed. All dependencies are already installed in
  `/app/node_modules`; the container has no network, so do not run
  `npm install` or add dependencies.
- The repository layout under `/app`:

  ```
  index.html
  package.json            <- entry point for "npm run build"
  vite.config.ts
  tsconfig.json
  src/main.tsx
  src/App.tsx
  src/pages/Home.tsx
  src/views/ChartsView.tsx
  src/views/ReportsView.tsx
  src/views/AdminView.tsx
  src/lib/...             <- generated heavy data modules (one per heavy view)
  src/styles.css
  ```

- Do not modify anything under `/app/node_modules`. Everything else under
  `/app` is fair game, and you are expected to change code and/or build
  configuration — the instruction deliberately does not tell you which files
  to touch; choose the design that meets the contract.

## Requirement 1 — the initial fetch must fit the byte budget

Rebuild with `cd /app && npm run build` and inspect `dist/`. The **initial
fetch** is defined as the total size, in bytes, of every JavaScript module the
browser must download before first render: the entry chunk referenced from
`dist/index.html`, anything it statically imports (transitively, excluding
lazy route chunks), plus any inline `<script type="module">` content.

- The initial fetch must be at most **400,000 bytes**.
- The emitted chunk graph must be genuinely split: `dist/assets` must contain
  at least **five** separate JS chunk files (today it contains one).

## Requirement 2 — heavy routes must load on demand

The three heavy views must be **code-split by route**: visiting `#/charts`,
`#/reports` or `#/admin` must fetch and execute that route's chunk only when
the route is visited, not up front. Concretely the emitted graph must satisfy
all of:

- each heavy view's code lands in its **own chunk** (one chunk per heavy
  view, separate from the entry and from each other);
- the entry chunk references each heavy-view chunk through a **dynamic
  import** (so the browser knows it is lazy), not a static one;
- the heavy data modules ship exactly once, inside the chunk of the view that
  uses them — the same module must not be duplicated into another chunk or
  into the entry.

## Requirement 3 — third-party vendor code must be split out

The framework code from `node_modules` (react, react-dom and friends) must
**not be part of the entry chunk** either: it must land in its own separate
vendor chunk that the entry statically imports. Configure this explicitly
rather than counting on default behaviour.

## Requirement 4 — the application must keep working

After the rebuild, the app must still function exactly as before, on every
route:

- `#/charts` renders the station table and its "Reseed chart" button; clicking
  the button changes the seed badge to a new `9f31:`-prefixed value;
- `#/reports` renders the template catalogue; the "Expand" button on the first
  template reveals its detail text;
- `#/admin` renders the audit index; the "Verify index" button fills the
  checksum badge with a `73b4:`-prefixed value;
- home (`#/`) renders the navigation links and all links navigate.

You can type-check locally with `npx tsc --noEmit` if you wish; type
correctness is not scored, but the built output must run.

## Deliverables

- `/app/package.json` — the entry point whose `build` script must produce the
  split output.
- `/app/dist` — the validated build output produced by `npm run build`.

## Success criteria

1. `cd /app && npm run build` exits 0.
2. The initial fetch (as defined above) is at most 400,000 bytes.
3. `dist/assets` contains at least five JS chunks; the three heavy views are
   each in their own lazily-loaded chunk, dynamically referenced from the
   entry, with their data modules not duplicated anywhere else.
4. react/react-dom vendor code is absent from the entry chunk and present in
   a separate vendor chunk.
5. All four routes render and behave as described above after the split.

The grader rebuilds the app from `/app/package.json` and `/app` itself and
scores the emitted chunk graph and the running application; making the build
small by deleting routes or features fails the routing and functionality
checks.