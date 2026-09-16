# bitts-longshore

No fixture files are shipped in this directory: the task's tree is the real
upstream **sympy/sympy** repository, cloned and checked out at a pinned
historical commit into `/app/src` by `environment/Dockerfile` at image build
time (see the comments there). The project is installed in editable mode, so
`import sympy` loads straight from `/app/src`.

Everything else you need is described in `/app/instruction.md` (workspace
copy) and in `instruction.md` at the task root.