# Embeddable content service (ECS)

You are the security engineer for ECS, a service that renders user-supplied HTML
fragments inside trusted pages. Every fragment is run through the DOMPurify
sanitizer to strip anything executable.

The DOMPurify library (source under `/app/src`, built distributable at
`/app/src/dist/purify.cjs`, full node toolchain under `/app/src/node_modules`)
is installed and warm. Use it exactly as installed — this is the real upstream
3.4.15 release.

`/app` is empty apart from this file. You will create two artifacts there:

- `/app/sanitize.js`
- `/app/bypass-test.js`

(Contract details are in `instruction.md`.)
