# hasp-plumb

The Redis 8.10.1 source tree lives at `/app/src` (pinned commit
`3399357e7c17b668289386b8a15a3037bc4527b1`); see /app/instruction.md for the
full task. Everything that matters lives under `/app`: build → configure →
ship `/app/start.sh` → the evaluator operates the server through its own
`/app/src/src/redis-cli`.