#!/bin/bash
# Oracle solution for item-032-hard.
set -euo pipefail

cat > /app/automate.py <<'PYEOF'
import os, pty, select, sys, time, json, tty, termios

COMMANDS = ["store gold","store silver","total","report","remove silver","total","report","quit"]


def render_raw(raw):
    """Render raw PTY bytes into plain visible text, honoring backspaces,
    carriage-return column resets, cursor-home/clear-screen escapes, and SGR."""
    rows = []
    line = []
    col = 0
    i = 0
    n = len(raw)

    def clear():
        rows.clear()
        line.clear()
        col = 0

    while i < n:
        c = raw[i]
        if c == 0x1b:
            if i + 1 < n and raw[i+1] == ord('['):
                j = i + 2
                while j < n and not (0x40 <= raw[j] <= 0x7e):
                    j += 1
                if j < n:
                    fin = raw[j]
                    param = raw[i+2:j].decode('latin-1')
                    if fin == ord('J') and ('2' in param or '3' in param):
                        clear()
                i = j + 1
                continue
            elif i + 1 < n and raw[i+1] == ord(']'):
                j = i + 2
                while j < n and raw[j] != 0x07:
                    if raw[j:j+2] == b'\x1b\\':
                        j += 2
                        break
                    j += 1
                i = j + 1
                continue
            else:
                i += 1
                continue
        elif c == 0x08:
            if col > 0 and col <= len(line):
                del line[col-1]
                col -= 1
            i += 1
            continue
        elif c == 0x0d:
            col = 0
            i += 1
            continue
        elif c == 0x0a:
            rows.append(''.join(line))
            line = []
            col = 0
            i += 1
            continue
        else:
            if col == len(line):
                line.append(chr(c))
            else:
                while len(line) < col:
                    line.append(' ')
                if col < len(line):
                    line[col] = chr(c)
                else:
                    line.append(chr(c))
            col += 1
            i += 1

    if line:
        rows.append(''.join(line))
    return '\n'.join(rows)


def main():
    pid, fd = pty.fork()
    if pid == 0:
        # Child: run app.py in a raw-mode terminal (no echo / CRLF translation),
        # so the captured byte stream is deterministic.
        os.environ.setdefault('TERM', 'xterm')
        try:
            tty.setraw(0)
        except Exception:
            pass
        try:
            tty.setraw(1)
        except Exception:
            pass
        os.chdir('/app')
        os.execv(sys.executable, [sys.executable, '/app/app.py'])

    buf = b''

    def read_available(timeout=0.5):
        nonlocal buf
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    d = os.read(fd, 65536)
                except OSError:
                    break
                if not d:
                    break
                buf += d

    def wait_bytes(tok, deadline=25.0):
        nonlocal buf
        end = time.time() + deadline
        while tok not in buf and time.time() < end:
            read_available(1.0)

    cursor = 0

    def consume_next_prompt(deadline=30.0):
        nonlocal buf, cursor
        end = time.time() + deadline
        while time.time() < end:
            idx = buf.find(b'> ', cursor)
            if idx != -1:
                cursor = idx + 2
                return
            read_available(1.0)

    # Phase A: login.
    wait_bytes(b'user: ')
    os.write(fd, b'admin\n')
    wait_bytes(b'pass: ')
    os.write(fd, b'abc123\n')

    # Phase B: consume first menu prompt then drive the command state machine.
    wait_bytes(b'> ', 30.0)
    first = buf.find(b'> ')
    cursor = first + 2 if first != -1 else 0

    for cmd in COMMANDS:
        os.write(fd, (cmd + '\n').encode())
        if cmd.lower() in ('quit', 'exit', 'q'):
            continue
        consume_next_prompt()

    # Drain until EOF.
    end = time.time() + 15.0
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                break
            if not d:
                break
            buf += d
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass

    rendered_full = render_raw(buf)
    idx = rendered_full.rfind('VAULT MENU')
    final = rendered_full[idx:] if idx != -1 else rendered_full

    with open('/app/transcript.txt', 'w') as f:
        f.write(rendered_full)
    with open('/app/final.txt', 'w') as f:
        f.write(final)
    with open('/app/log.json', 'w') as f:
        json.dump({"commands": COMMANDS}, f)


if __name__ == '__main__':
    main()
PYEOF

python3 /app/automate.py
echo "done"