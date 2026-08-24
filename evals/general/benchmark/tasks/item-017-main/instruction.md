# Recover the secret from a password-protected 7z archive

`/app/vault.7z` is a (non-encrypted) 7-Zip archive that you can open with the `7z` command.
Inside it there is an **encrypted** sub-archive, `secret.7z`, whose password you must first
determine. Your goal is to read `secret.txt` from inside `secret.7z` and write its exact
contents to `/app/recovered.txt`.

## What is inside `vault.7z`

Extract `/app/vault.7z` (e.g. `7z x /app/vault.7z -o/app/vault`) and you will find:

- `clue.txt` — background notes.
- `hash.txt` — the password hash we need to crack.
- `wordlist.txt` — a candidate password dictionary (one word per line).
- `secret.7z` — the encrypted target archive (contains `secret.txt`).

## Do this

1. **Extract** `/app/vault.7z` with the `7z` command-line tool (`7z x ...`).
2. **Inspect `hash.txt`**: it is a cryptographic hash of the vault password — specifically a
   raw MD5 hash. Do not brute-force a salted guess; extract the hash line and crack it with a
   dictionary.
3. **Crack the hash** with John the Ripper (`john`) using the bundled wordlist as a
   dictionary:
   ```
   john --wordlist=/app/vault/wordlist.txt --format=Raw-MD5 /app/vault/hash.txt
   ```
   After cracking, retrieve the recovered plaintext (e.g. `john --show ...`).
4. **Open the encrypted archive** using the recovered password to get the file out:
   ```
   7z x /app/vault/secret.7z -o/app/out -p<PASSWORD>
   ```
   (The `-p` flag passes the password on the command line; quote it if it has special
   characters.)
5. Read `secret.txt` from the output directory and write its exact trimmed contents to
   `/app/recovered.txt`.

## Constraints / notes

- All tools you need (`7z`, `john`) are already installed.
- The password is a single dictionary word present in `wordlist.txt`; keep that in scope when
  choosing attack options.
- `secret.txt` contains a single short flag line with no surrounding whitespace beyond a
  trailing newline. `/app/recovered.txt` must contain exactly that flag.

## Success criterion

`/app/recovered.txt` exists and contains the exact flag text recovered from
`/app/vault/secret.7z`.