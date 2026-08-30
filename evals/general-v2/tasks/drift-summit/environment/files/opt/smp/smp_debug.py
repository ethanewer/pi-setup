#!/usr/bin/env python3
"""smp_debug.py - interactive instruction-level debugger for the SMP machine.

SMP (Simple Machine Program) is a small stack machine with 8 registers
(R0..R7), an operand stack, and a fixed 16-bit address space. A program is a
text file with one instruction per line:

    <hex-address> <OP> [operand]

Addresses must be contiguous starting at any base (typically 0x0000).

The debugger is driven interactively: it reads one line command at a time from
stdin. Commands:

    load <path>          load a program image (validates layout and jump targets)
    list                 print the loaded program
    step                 execute exactly one instruction (alias: s)
    trace <n>            execute up to <n> instructions, printing each
                         executed address (alias: t, si)
    run                  execute until HALT
    regs                 print pc, halted flag, registers, stack depth (alias: r)
    stack                print the operand stack, top first (alias: st)
    help                 list commands (alias: h)
    quit                 exit (alias: q, exit)

Every executed instruction is reported as a single line:

    exec 0xXXXX

When the HALT instruction is executed the debugger also prints:

    halt 0xXXXX

and does not execute further instructions. If a trace/run ends without HALT a
summary line is printed:

    stopped pc=0xXXXX after N steps

No banner or prompt is emitted when stdin is not a terminal, so piped command
sequences produce a clean, parseable transcript.
"""

import sys

OPS = {
    "PUSH": 1,  # push integer operand
    "LOAD": 1,  # push R<operand>
    "STORE": 1,  # pop into R<operand>
    "JMP": 1,   # unconditional jump to hex address operand
    "JZ": 1,    # pop; jump if zero
    "JNZ": 1,   # pop; jump if nonzero
    "POP": 0, "ADD": 0, "SUB": 0, "MUL": 0, "DIV": 0,
    "DUP": 0, "SWAP": 0, "OUT": 0, "HALT": 0,
}


class VM:
    def __init__(self):
        self.prog = {}         # addr -> [op, operand]
        self.order = []        # contiguous addresses
        self.base = 0
        self.maxa = 0
        self.pc = 0
        self.stack = []
        self.regs = [0] * 8
        self.halted = False
        self.halt_addr = None
        self.loaded = False

    # ---- loading ----
    def load(self, path):
        try:
            with open(path) as fh:
                raw = fh.readlines()
        except OSError:
            return "error: cannot load %s" % path
        prog, order = {}, []
        for ln in raw:
            s = ln.strip()
            if not s or s.startswith("#"):
                continue
            tok = s.split()
            if len(tok) not in (2, 3):
                return "error: bad instruction '%s'" % s
            try:
                addr = int(tok[0], 16)
            except ValueError:
                return "error: bad address '%s'" % tok[0]
            op = tok[1].upper()
            if op not in OPS:
                return "error: unknown op '%s'" % op
            if OPS[op] == 1:
                if len(tok) != 3:
                    return "error: missing operand '%s'" % s
                oper = tok[2]
                if op == "PUSH":
                    try:
                        oper = int(oper, 10)
                    except ValueError:
                        return "error: bad push operand '%s'" % oper
                elif op in ("LOAD", "STORE"):
                    try:
                        oper = int(oper, 10)
                    except ValueError:
                        return "error: bad register '%s'" % oper
                    if not 0 <= oper <= 7:
                        return "error: register out of range '%s'" % oper
                else:  # jumps
                    try:
                        oper = int(oper, 16)
                    except ValueError:
                        return "error: bad jump target '%s'" % oper
            else:
                oper = None
            prog[addr] = [op, oper]
            order.append(addr)
        if not order:
            return "error: empty program"
        base = order[0]
        for i, a in enumerate(order):
            if a != base + i:
                return "error: non-contiguous addresses"
        for a in order:
            op, oper = prog[a]
            if op in ("JMP", "JZ", "JNZ") and oper not in prog:
                return "error: jump target 0x%04x not present" % oper
        self.prog, self.order = prog, order
        self.base, self.maxa = base, order[-1]
        self.pc = base
        self.stack = []
        self.regs = [0] * 8
        self.halted = False
        self.halt_addr = None
        self.loaded = True
        return "program %s loaded: %d instructions base=0x%04x max=0x%04x" % (
            path, len(order), base, order[-1])

    # ---- execution ----
    def _underflow(self):
        self.halted = True
        self.halt_addr = self.pc
        return "error: stack underflow"

    def step(self):
        """Execute one instruction. Returns list of output lines."""
        if not self.loaded:
            return ["error: no program loaded"]
        if self.halted:
            return ["error: program halted"]
        a = self.pc
        op, oper = self.prog[a]
        out = []
        err = None
        st = self.stack
        try:
            if op == "PUSH":
                st.append(oper)
            elif op == "LOAD":
                st.append(self.regs[oper])
            elif op == "STORE":
                if not st:
                    err = self._underflow()
                else:
                    self.regs[oper] = st.pop()
            elif op == "POP":
                if not st:
                    err = self._underflow()
                else:
                    st.pop()
            elif op in ("ADD", "SUB", "MUL", "DIV"):
                if len(st) < 2:
                    err = self._underflow()
                else:
                    b, a_ = st.pop(), st.pop()
                    if op == "ADD":
                        st.append(a_ + b)
                    elif op == "SUB":
                        st.append(a_ - b)
                    elif op == "MUL":
                        st.append(a_ * b)
                    else:
                        if b == 0:
                            self.halted = True
                            self.halt_addr = a
                            err = "error: division by zero"
                        else:
                            st.append(a_ // b)
            elif op == "DUP":
                if not st:
                    err = self._underflow()
                else:
                    st.append(st[-1])
            elif op == "SWAP":
                if len(st) < 2:
                    err = self._underflow()
                else:
                    st[-1], st[-2] = st[-2], st[-1]
            elif op == "OUT":
                if not st:
                    err = self._underflow()
                else:
                    out.append("out %d" % st.pop())
            elif op in ("JMP", "JZ", "JNZ"):
                v = None
                if op != "JMP":
                    if not st:
                        err = self._underflow()
                    else:
                        v = st.pop()
                if op == "JMP" or (op == "JZ" and v == 0) or (op == "JNZ" and v != 0):
                    self.pc = oper
                else:
                    self.pc = a + 1
            elif op == "HALT":
                self.halted = True
                self.halt_addr = a
            else:
                return ["error: unknown op %s" % op]
        except Exception as exc:  # pragma: no cover - defensive
            return ["error: internal %r" % exc]

        if not self.halted and err is None:
            # advance program counter unless a jump already set it
            if self.pc == a:
                nxt = self.order.index(a) + 1
                self.pc = self.order[nxt] if nxt < len(self.order) else self.maxa + 1
        out.append("exec 0x%04x" % a)
        if self.halted:
            out.append("halt 0x%04x" % self.halt_addr)
        return out

    def trace(self, n):
        if not self.loaded:
            return ["error: no program loaded"]
        if n <= 0:
            return ["error: trace steps must be positive"]
        out = []
        done = 0
        for _ in range(n):
            if self.halted:
                break
            out += self.step()
            done += 1
        if not self.halted:
            out.append("stopped pc=0x%04x after %d steps" % (self.pc, done))
        return out

    def run(self):
        if not self.loaded:
            return ["error: no program loaded"]
        out, done = [], 0
        while not self.halted:
            out += self.step()
            done += 1
            if done > 1000000:
                out.append("error: runaway program")
                break
        return out


def main():
    vm = VM()
    interactive = sys.stdin.isatty()
    if interactive:
        print("smp> type 'help' for commands")
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        tok = line.split()
        cmd = tok[0].lower()
        args = tok[1:]
        if cmd in ("q", "quit", "exit"):
            break
        elif cmd == "load":
            if len(args) != 1:
                print("error: usage: load <path>")
                continue
            print(vm.load(args[0]))
        elif cmd in ("l", "list"):
            if not vm.loaded:
                print("error: no program loaded")
                continue
            for a in vm.order:
                op, oper = vm.prog[a]
                tail = (" %s" % oper) if oper is not None else ""
                print("0x%04x %s%s" % (a, op, tail))
        elif cmd in ("s", "step"):
            for ln in vm.step():
                print(ln)
        elif cmd in ("t", "si", "trace"):
            if len(args) != 1:
                print("error: usage: trace <n>")
                continue
            try:
                n = int(args[0], 10)
            except ValueError:
                print("error: bad step count '%s'" % args[0])
                continue
            for ln in vm.trace(n):
                print(ln)
        elif cmd == "run":
            for ln in vm.run():
                print(ln)
        elif cmd in ("r", "regs"):
            if not vm.loaded:
                print("error: no program loaded")
                continue
            regs = " ".join("r%d=%d" % (i, vm.regs[i]) for i in range(8))
            print("pc=0x%04x halted=%s %s sp=%d" % (
                vm.pc, "yes" if vm.halted else "no", regs, len(vm.stack)))
        elif cmd in ("st", "stack"):
            topfirst = list(reversed(vm.stack))
            print("stack=[%s]" % ", ".join(str(v) for v in topfirst))
        elif cmd in ("h", "help"):
            print("commands: load <path>, list, step, trace <n>, run, regs, stack, help, quit")
        elif cmd.startswith("load "):
            print("error: unknown command '%s'" % line)
        else:
            print("error: unknown command '%s'" % line)
    sys.stdout.flush()


if __name__ == "__main__":
    main()