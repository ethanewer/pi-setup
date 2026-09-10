# Excited-state population of a driven two-level system with QuTiP

## Environment

- **QuTiP 5.3.1** is installed into this container's Python environment. It was
  built and installed from source at build time from a pinned checkout of the
  upstream repository `qutip/qutip`, which lives at **`/app/src`** and is
  readable there so you can explore the library's API. `import qutip` works in
  any fresh interpreter.
- The numeric stack (`numpy`, `scipy`) is already installed. The container has
  **no network**: do not try to `pip install` anything; it will fail.
- The machine is budgeted at one CPU; keep the program lightweight.

## The computation

A two-level quantum system (a spin-1/2) is prepared in the ground state
`|0>`. It evolves for a time `T` under the time-independent Hamiltonian

```
H = -(delta/2) sigma_z + (omega/2) sigma_x
```

where `sigma_z` and `sigma_x` are the Pauli matrices and `delta`, `omega` are
real parameters (in units where hbar = 1).

Your program must evolve `|0>` to time `T` and report the **excited-state
population** at the final time:

```
P1(T) = |<1| exp(-i H T) |0>|^2
```

i.e. the probability that the system is found in the excited state `|1>` after
evolving for the full time `T`.

## The deliverable

Write a Python program at **`/app/quantum_dynamics.py`** that:

1. takes exactly three command-line arguments — `delta`, `omega`, `T` (all
   real numbers, this ordering);
2. builds the Hamiltonian above and the two relevant states/operators
   **using QuTiP's own objects** (its operator, state and solver functions),
   and performs the evolution with QuTiP's solver machinery — not by
   hand-rolling the matrix exponentiation in numpy;
3. prints, as **a single floating-point number on its own line** (and nothing
   else on stdout), the value of `P1(T)` for the given parameters.

Example invocation:

```
python3 /app/quantum_dynamics.py 0.5 1.0 12.5
0.3355909929
```

The number on stdout is what will be checked against an independently computed
reference value for the same `(delta, omega, T)`, so it must be the excited-
state population accurate to a few parts in ten thousand.

The QuTiP API you need (operators, `qutip.sigmaz`/`qutip.sigmax`, state
construction, and a solver such as `qutip.sesolve` or `qutip.mesolve`) is
available in the installed package and documented in the `/app/src` checkout.
Which solver to use, how finely to sample the evolution, and how to extract the
final expectation value are your design decisions — the only requirements are
the physics above, the CLI, and that the linear algebra runs through QuTiP's
own operators and solver.

## Deliverable summary

- `/app/quantum_dynamics.py` — the program described above (required).
