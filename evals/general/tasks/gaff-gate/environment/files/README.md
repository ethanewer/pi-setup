# gaff-gate — working tree notes

You are working inside a real upstream repository. Read `instruction.md` for
the task. The repository lives at `/app/src`; its dependencies are already
installed (`/app/src/node_modules`).

Everything you need to run and test the project is on disk. No network is
available or guaranteed during the trial, so do not attempt to install or
fetch anything: it will not work, and modifying what is on disk in an attempt
to simulate an install will not help.

Remember: `/app/src` is a git repository pinned to a fixed commit. `git log`
and `git status` are your friends; the project's own test suite is runnable
with the mocha binary in `/app/src/node_modules/.bin/mocha`.