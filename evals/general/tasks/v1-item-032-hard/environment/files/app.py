import sys
import time

# A "terminal vault". Three-phase state machine:
#   A) login (user/pass)  ->  B) authenticated menu  ->  C) quit/logout.
# The menu supports storing items, reporting and removing them. Storing shows a
# brief backspace-based progress animation that a driver must render correctly.
vals = {}


def emit(text):
    sys.stdout.write(text)
    sys.stdout.flush()


def main():
    # Phase 1: interactive login. Refuses to proceed until the correct
    # credentials are typed (a state machine: only 'admin'/'abc123' transition).
    emit("\x1b[1;35mVAULT\x1b[0m\n")
    while True:
        emit("user: ")
        u = input().strip()
        if u == "admin":
            break
        emit("invalid user\n")
    while True:
        emit("pass: ")
        p = input().strip()
        if p == "abc123":
            break
        emit("invalid pass\n")

    # Phase 2: clear the screen and show the authenticated menu.
    emit("\x1b[2J\x1b[H")
    emit("VAULT MENU\n")
    emit("store <name> | total | report | remove <name> | quit\n")

    while True:
        emit("> ")
        line = input()
        line = line.strip()
        if not line:
            continue
        parts = line.split(maxsplit=1)
        cmd = parts[0].lower()
        arg = parts[1].strip() if len(parts) > 1 else ""
        if cmd == "store":
            if arg:
                # simulate a slow operation with a backspace-overwrite animation.
                emit("saving")
                for _ in range(3):
                    emit(".")
                    time.sleep(0.05)
                emit("\b" * 9)  # overwrite "saving..." to nothing
                vals[arg] = True
                emit("stored: " + arg + "\n")
            else:
                emit("store needs a name\n")
        elif cmd == "remove":
            if arg in vals:
                del vals[arg]
                emit("removed: " + arg + "\n")
            else:
                emit("unknown item: " + arg + "\n")
        elif cmd == "total":
            emit("total: " + str(len(vals)) + "\n")
        elif cmd == "report":
            for k in vals:
                emit(" - " + k + "\n")
            emit("total: " + str(len(vals)) + "\n")
        elif cmd in ("quit", "exit", "q"):
            emit("logged out\n")
            break
        else:
            emit("unknown command: " + cmd + "\n")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    main()