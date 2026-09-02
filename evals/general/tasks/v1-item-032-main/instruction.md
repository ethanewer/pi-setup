# Drive an interactive terminal program with a PTY

In `/app` there is an interactive program, `vault.sh` (run it with
`bash /app/vault.sh`). It behaves like a terminal vault lock:

- On start it **clears the screen** and prints a coloured banner using ANSI
  escape sequences.
- It asks **three arithmetic gates**, one after another, with coloured prompts
  of the form `gate N: A op B = ?` (e.g. `gate 1: 17 + 19 = ?`).
- It reads each answer from the terminal. If the answer is wrong it prints
  `no.` and re-asks the same question; a correct answer advances to the next
  gate.
- After three correct answers it prints `OPEN`, waits a moment, then prints the
  **golden token** — a line of the form `GOLDEN-<number>` — split into two
  chunks with a delay in between (so naive one-shot reads will miss half of
  it).
- The program reads input with `read -s`, which **requires a real terminal**:
  if you feed it from a plain pipe it fails immediately. You must attach a
  **pseudo-terminal** (PTY) and drive it like a real user would.

## Your task

Write a Python driver `/app/driver.py` that:

1. Spawns `bash /app/vault.sh` connected to a **PTY** (use the standard
   library `pty` module).
2. Reads the program's output in small chunks as it arrives (it is
   interactive — there is no "end" until the vault closes), tolerating
   **partial reads** and the `\r` line endings a terminal produces.
3. **Strips the ANSI escape sequences** from the output so it can find the
   actual prompts.
4. Parses each arithmetic question, computes the answer, and types it back
   (this is a full interactive dialogue: question -> answer -> next question).
5. After the vault opens, collects the printed token (even though it arrives
   in pieces), and writes **exactly the token line** (e.g. `GOLDEN-2112`, no
   trailing spaces) to `/app/result.txt`.

Run your driver so that `/app/result.txt` exists with the correct content.

## Checks that will be run

- `bash /app/vault.sh` really opens when driven through a PTY with the correct
  answers (the interactive behaviour is verified directly).
- `/app/result.txt` is (re)produced by running `bash /app/driver.py` and its
  content matches the token the vault prints.

Notes: do not modify `vault.sh`. The driver must be able to start from a clean
state (the result file will be deleted before it is run). Handle the timing
generously but do not hang forever — if the dialogue fails the driver should
exit with a non-zero status.