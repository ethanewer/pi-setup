# jib-weir environment readme

What is already set up in this container. Network is disabled at trial time.

## Toolchain

- Node.js 22.23.2 and npm 10.9.8 are on PATH (`node`, `npm`).
- TypeScript 5.9.3 compiler at `/app/node_modules/.bin/tsc`. Its type
  declarations for the Node runtime ship with `@types/node` 22.20.1.
- Python 3.11 is available as `python3` (a handy HTTP test client; no
  guarantee `curl` exists).

## Vendored dependencies (do not `npm install` — there is no registry)

Installed at `/app/node_modules`, exact versions:

| package                          | version  |
|----------------------------------|----------|
| express                          | 4.22.1   |
| zod                              | 3.25.75  |
| @asteasolutions/zod-to-openapi   | 3.4.0    |
| @types/express                   | 4.17.25  |
| @types/node                      | 22.20.1  |
| typescript                       | 5.9.3    |

If your project declares these dependencies in its own `package.json`, use the
same versions so the baked tree satisfies npm metadata checks.

## Files

- `/app/data/media.json` — the visible seed dataset (read-only input).
- `/app/README-env.md` — this file.

## Constraints

- No network: `npm install`, `npm cache`, `apt-get update` all fail at trial
  time. Everything must already be on disk.
- Bind servers to `127.0.0.1`; the container has no external network anyway.
- The verifier invokes `/app/start.sh PORT DATA_FILE` and probes the HTTP
  surface; ports 9450-9453 are reserved for the verifier, 8780-8799 are free
  for your own testing.