# bracket-beacon task image

This image exists for one task: repair a security bug in the real DOMPurify
checkout at `/app/src`.

Read `instruction.md` in the task directory for the full brief; the short
version is that a function-form `ADD_ATTR` callback lets dangerous URI schemes
such as `javascript:` pass through the sanitizer untouched, while the array
form and the defaults strip them.

- `/app/src` — the buggy checkout (see its own `README.md` for the project).
- `/app/repro.js` — a working reproduction; exits 1 while the bug is present.
- The build is `npm run build` from `/app/src`; the jsdom test suite is
  `node test/jsdom-node-runner` from `/app/src`.

Everything is installed; there is no network.