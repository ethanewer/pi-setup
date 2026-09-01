#!/usr/bin/env bash
# willow-wharf oracle: author every deliverable and run the toolchains that
# produce the checked logs. Runs from a pristine container (/app only).
set -euo pipefail

# ----------------------------------------------------------------------
# 1) Coq proof - complete the induction and check it.
# ----------------------------------------------------------------------
cat > /app/proof.v <<'COQEOF'
(* Willow Wharf - proof module (completed by the consultant). *)
Require Import Arith Lia.

(* Sum of the first few non-negative naturals, accumulated upward. *)
Fixpoint sumup (n : nat) : nat :=
  match n with
  | O   => O
  | S k => sumup k + S k
  end.

(* The same summation accumulated downward (report appendix). *)
Fixpoint sumdown (n : nat) : nat :=
  match n with
  | O   => O
  | S k => S k + sumdown k
  end.

Theorem sumup_eq_sumdown : forall n : nat, sumup n = sumdown n.
Proof.
  induction n as [ | n' IHn ].
  - (* base 0 *) reflexivity.
  - (* step *) simpl. rewrite IHn. lia.
Qed.
COQEOF

cd /app
coqc proof.v > /app/proof-check.log 2>&1

# ----------------------------------------------------------------------
# 2) Sympy symbolic integrator.
# ----------------------------------------------------------------------
cat > /app/integral.py <<'PYEOF'
#!/usr/bin/env python3
"""Willow Wharf symbolic integrator over the unit interval.

  python3 /app/integral.py [EXPR]
integrates the given sympy EXPR over x in [0,1] and prints the exact
simplified closed form. No argument uses the fixed client integral
4/(1+x**2) over [0,1], whose closed form is pi. Unparseable input is an
error: one line on stderr and exit status 2.
"""
import sys
import sympy as sp


def closed_form(expr_text):
    x = sp.Symbol("x")
    expr = sp.sympify(expr_text)
    value = sp.integrate(expr, (x, 0, 1))
    return str(sp.simplify(sp.expand(value)))


def main():
    expr_text = sys.argv[1] if len(sys.argv) > 1 else "4/(1+x**2)"
    try:
        out = closed_form(expr_text)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"integral: cannot integrate {expr_text!r}: {exc}\n")
        sys.exit(2)
    print(out)


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/integral.py

python3 /app/integral.py > /app/integral.txt

# ----------------------------------------------------------------------
# 3) R sampler + self test.
# ----------------------------------------------------------------------
cat > /app/sampler.R <<'REOF'
# Willow Wharf sampler: Monte-Carlo estimate of int_0^1 x^a dx = 1/(a+1).
# The two client-required entry points must keep these exact names.

willow_sample <- function(n = 2000L, a = 2.0) {
    stopifnot(is.numeric(n), n >= 1L, is.numeric(a))
    set.seed(20260701L)          # reproducible
    xs <- stats::runif(as.integer(n))
    mean(xs ^ a)
}

willow_selftest <- function(n = 4000L, a = 2.0, tol = 0.02) {
    est <- willow_sample(n, a)
    ref <- 1.0 / (a + 1.0)
    ok <- is.finite(est) && abs(est - ref) <= tol
    cat(sprintf("willow_selftest: sample=%.5f ref=%.5f %s\n",
                est, ref, if (ok) "PASS" else "FAIL"))
    if (!ok) {
        quit(status = 1L)
    }
    invisible(ok)
}
REOF

cd /app
Rscript -e 'source("/app/sampler.R"); willow_selftest()' > /app/selftest.log 2>&1

# ----------------------------------------------------------------------
# 4) LaTeX report: synonym-substituted so pdflatex builds warning-free.
# ----------------------------------------------------------------------
cat > /app/report.tex <<'TEXEOF'
\documentclass[11pt]{article}
\usepackage[margin=1.2in]{geometry}
\pagestyle{empty}
\setlength{\parindent}{0pt}
\begin{document}
{\Large\textbf{Willow Wharf --- monthly client memo}}\\[4pt]
\textit{Prepared for Braken Tide Consulting by the Willow quantitative
research consultancy.}

This memo summarises the replicated estimate of our named definite integral
and prescribes the reporting conventions for third-party reproductions.

\textbf{Memo body.} The integrator returns the closed form exactly and the
sampler restores the same constant within tolerance on every run. The proof is
checked by \texttt{coqc} without any admitted obligation, and the report is
compiled with \texttt{pdflatex} so that no line overflows its box. Every
rendered paragraph avoids long unbroken electrohydromagnetic metering terms,
because an unbreakable token that is wider than the column forces the
typesetter to overfill a box.
\end{document}
TEXEOF

rm -rf /tmp/wwbuild && mkdir -p /tmp/wwbuild
cp /app/report.tex /tmp/wwbuild/
cd /tmp/wwbuild
pdflatex -interaction=nonstopmode -halt-on-error report.tex > /tmp/pd1.log 2>&1
cp report.log /app/pdflatex.log
cp report.pdf /app/report.pdf

echo "willow-wharf oracle complete"
ls -l /app/proof.v /app/proof-check.log /app/integral.py /app/integral.txt \
      /app/sampler.R /app/selftest.log /app/report.tex /app/report.pdf /app/pdflatex.log