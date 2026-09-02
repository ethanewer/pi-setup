import sys

items = []


def emit(text):
    sys.stdout.write(text)
    sys.stdout.flush()


def show_banner():
    # ANSI: [1;36m = bold cyan. A real terminal renders this as colored text.
    emit("\x1b[1;36mLOG-BOOK\x1b[0m\r\nadd <name> | remove <name> | total | report | quit\r\n")


def main():
    show_banner()
    while True:
        emit("> ")
        try:
            line = input()
        except EOFError:
            break
        line = line.strip()
        if not line:
            continue
        parts = line.split(maxsplit=1)
        cmd = parts[0].lower()
        arg = parts[1].strip() if len(parts) > 1 else ""
        if cmd == "add":
            if arg:
                items.append(arg)
                emit("added: " + arg + "\r\n")
            else:
                emit("unknown command: add\r\n")
        elif cmd == "remove":
            if arg in items:
                items.remove(arg)
                emit("removed: " + arg + "\r\n")
            else:
                emit("unknown item: " + arg + "\r\n")
        elif cmd == "total":
            emit("total: " + str(len(items)) + "\r\n")
        elif cmd == "report":
            for it in items:
                emit(" - " + it + "\r\n")
            emit("total: " + str(len(items)) + "\r\n")
        elif cmd in ("quit", "exit", "q"):
            emit("goodbye\r\n")
            break
        else:
            emit("unknown command: " + cmd + "\r\n")


if __name__ == "__main__":
    # Ensure the child sees a proper terminal environment even if inherited env
    # is lacking (rescuing a fresh python launch).
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    main()