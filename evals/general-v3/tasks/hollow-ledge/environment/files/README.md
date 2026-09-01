# Hollow Ledge rescue

A vault (`ledge.db`) and its write-ahead log were hit by a byte-cipher. Two
artifacts must be recovered, then you must record the recovered credentials.
The full task brief is in `/app/../instruction.md` at the workspace root.

Things you find in `/app`:

| path | meaning |
|------|---------|
| `ledge.db` | main SQLite ledger DB (WAL mode). The private `cfg` rows were written-but-never-checkpointed, so they live ONLY in the WAL, which is why the WAL matters. |
| `ledge.db-wal.obf` | the ledger's WAL, byte-obfuscated with a **single one-byte key** by XOR, applied to every byte (per public spec: the byte transform is `x ^ key`). |
| `carrier.bin` | a stale log thumbnail that carries deleted material: a private key and its certificate, each a length-prefixed PEM blob (markers `LVPR` / `LVCR`, then `<u32 LE length>` then the PEM bytes). |
| `src/check.c` | the vault's password-validation routine. A pre-built `ledgecheck` binary is installed at `/usr/local/bin/ledgecheck`. |
| `instruction.md` | the full self-contained briefing (authoritative). |