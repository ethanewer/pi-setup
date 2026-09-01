#!/usr/bin/env bash
# Zephyr Summit oracle: builds every deliverable for real.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "== 1. install clean-room compiler -> /app/vendor/bin/cc =="
mkdir -p /app/vendor/bin
# The clean-room C-subset compiler source is vendored at /app/cc-src/cc.py.
# Install it as the on-demand deliverable compiler driver.
install -m 755 /app/cc-src/cc.py /app/vendor/bin/cc
cat > /tmp/smoke.c <<'EOF'
#include <stdio.h>
int main(void){ printf("%d\n", 6*7); return 0; }
EOF
/app/vendor/bin/cc -o /tmp/smoke /tmp/smoke.c
[ "$(/tmp/smoke)" = "42" ] || { echo "compiler smoke test failed"; exit 1; }
echo "ok: clean-room cc compiles and runs"

echo "== 2. compile probe + emit sections.txt =="
mkdir -p /app/bin
/app/vendor/bin/cc -o /app/bin/probe /app/fixtures/probe.c
readelf --wide --sections /app/bin/probe > /app/sections.txt
printf '\n== SYMBOLS ==\n' >> /app/sections.txt
readelf --wide --syms /app/bin/probe >> /app/sections.txt

echo "== 3. scala assembly jar =="
mkdir -p /app/artifact /tmp/scbuild
cd /tmp/scbuild
cp /app/fixtures/scalademo/*.scala .
mkdir -p classes
scalac -d classes Adder.scala Runner.scala
printf 'Main-Class: summit.Runner\n' > manifest.txt
jar cfm /app/artifact/runner.jar manifest.txt -C classes .
mkdir -p rt && cd rt && jar xf /usr/share/java/scala-library.jar
rm -rf META-INF
cd /tmp/scbuild && jar uf /app/artifact/runner.jar -C rt scala
java -jar /app/artifact/runner.jar 2 3

echo "== 4. coq proof object =="
mkdir -p /app/proofs
cat > /app/proofs/thm.v <<'COQ'
(*** Zephyr Summit proof module -- completed. ***)
Require Import Coq.Lists.List Coq.Arith.PeanoNat Lia.
Import ListNotations.
Open Scope nat_scope.

Fixpoint lsum (s : list nat) : nat :=
  match s with [] => 0 | n :: t => n + lsum t end.

Lemma lsum_app : forall l m : list nat,
    lsum (l ++ m) = lsum l + lsum m.
Proof.
  intros. induction l as [|a t IH]; simpl.
  - lia.
  - rewrite IH. lia.
Qed.

Fixpoint rep (x n : nat) : list nat :=
  match n with 0 => [] | S k => x :: rep x k end.

Lemma lsum_rep : forall n x : nat, lsum (rep x n) = n * x.
Proof.
  intros. induction n; simpl.
  - lia.
  - rewrite IHn. lia.
Qed.

Fixpoint revA {A : Type} (l : list A) : list A :=
  match l with [] => [] | h :: t => revA t ++ [h] end.

Lemma revA_app : forall (A : Type) (l m : list A),
    revA (l ++ m) = revA m ++ revA l.
Proof.
  intros A l m. induction l as [|h t IH]; simpl.
  - rewrite app_nil_r. reflexivity.
  - rewrite IH. rewrite app_assoc. reflexivity.
Qed.

Lemma revA_length : forall (A : Type) (l : list A),
    length (revA l) = length l.
Proof.
  intros A l. induction l as [|h t IH]; simpl.
  - reflexivity.
  - rewrite app_length. simpl. lia.
Qed.

Fixpoint sum_upto (n : nat) : nat :=
  match n with 0 => 0 | S k => sum_upto k + n end.

Lemma gauss : forall n : nat, sum_upto n * 2 = n * (n + 1).
Proof.
  intro n. induction n as [|k IH]; simpl.
  - lia.
  - nia.
Qed.

Theorem summit : forall l m : list nat,
    lsum (l ++ m) = lsum m + lsum l.
Proof.
  intros. rewrite lsum_app. lia.
Qed.
COQ
cd /app/proofs && coqc thm.v
cp thm.vo thm

echo "== 5. symbolic execution engine =="
mkdir -p /app/bin
cat > /app/bin/symexec <<'PY'
#!/opt/z3venv/bin/python
import sys, json
import z3

def mk_cmp(cm, a, b):
    if cm == "LT": return a < b
    if cm == "LE": return a <= b
    if cm == "GT": return a > b
    if cm == "GE": return a >= b
    if cm == "NE": return a != b
    return a == b

def lookup(env, x):
    if isinstance(x, int): return z3.IntVal(x)
    return env[x]

def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        import subprocess, os
        z3ver = ".".join(str(v) for v in z3.get_version())
        okll = (subprocess.call(["which", "clang-16"], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL) == 0
                and os.path.exists("/usr/bin/llvm-config-16"))
        print("SELFTEST_OK z3=%s llvm16=%s" % (z3ver, "yes" if okll else "no"))
        return
    spec = json.load(open(sys.argv[1]))
    names = list(spec["vars"].keys())
    X = {n: z3.Int(n) for n in names}
    s = z3.Solver()
    for n in names:
        lo, hi = spec["vars"][n]; s.add(X[n] >= lo, X[n] <= hi)
    env = dict(X)
    for op in spec["ops"]:
        k, dst = op["op"], op["dst"]
        if k == "set": env[dst] = z3.IntVal(op["val"])
        elif k == "neg": env[dst] = -lookup(env, op["a"])
        elif k == "ite":
            lhs, cm, rhs = op["cond"]
            env[dst] = z3.If(mk_cmp(cm, lookup(env, lhs), lookup(env, rhs)),
                             lookup(env, op["a"]), lookup(env, op["b"]))
        elif k in ("add", "sub", "mul"):
            a = lookup(env, op["a"]); b = lookup(env, op["b"])
            env[dst] = {"add": a + b, "sub": a - b, "mul": a * b}[k]
        else:
            raise ValueError("bad op " + k)
    s.add(env[spec["goal"]["var"]] == spec["goal"]["eq"])
    sols = []
    while s.check() == z3.sat:
        m = s.model()
        tup = tuple(m[X[n]].as_long() for n in names)
        sols.append(tup)
        s.add(z3.Or(*[X[n] != v for n, v in zip(names, tup)]))
    sols = sorted(sols)
    if not sols:
        print("NO_SOLUTION"); return
    for t in sols:
        print(",".join("%s=%d" % (n, v) for n, v in zip(names, t)))
main()
PY
chmod +x /app/bin/symexec

echo "== verify all deliverables exist =="
ls -la /app/vendor/bin/cc /app/sections.txt /app/proofs/thm /app/proofs/thm.v /app/proofs/thm.vo /app/artifact/runner.jar /app/bin/symexec
echo "SOLVE_COMPLETE"