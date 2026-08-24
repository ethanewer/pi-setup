#!/bin/bash
set -euo pipefail

cat > /app/prog.py <<'EOF'
import sys, argparse

def main(argv):
    if '--version' in argv:
        sys.stdout.write("myapp version 2.3.0\n")
        return 0
    if '--help' in argv:
        sys.stdout.write("Usage: prog [--name NAME] FILE\n")
        return 0
    name = None
    file_arg = None
    i = 0
    args = list(argv)
    while i < len(args):
        a = args[i]
        if a == '--name':
            if i + 1 >= len(args):
                print("error: --name requires a value", file=sys.stderr)
                return 2
            name = args[i+1]
            i += 2
        elif a.startswith('--'):
            print("error: unknown flag %s" % a, file=sys.stderr)
            return 2
        else:
            if file_arg is None:
                file_arg = a
            i += 1
    if file_arg is None:
        print("error: FILE argument required", file=sys.stderr)
        return 2
    with open(file_arg) as f:
        for line in f:
            if name is not None:
                sys.stdout.write(name + "> " + line)
            else:
                sys.stdout.write(line)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
EOF
echo "written /app/prog.py"