#!/usr/bin/env python3
"""Quantum-dynamics solver for the tenon-orbit task.

Given the parameters (delta, omega, T) of a driven two-level system, evolve the
ground state |0> under the Hamiltonian

    H = -(delta/2) sigma_z + (omega/2) sigma_x

for a time T and report the excited-state (spin-up) population P1(T) =
|<1| exp(-i H T) |0>|^2, computed with QuTiP's own operators and solver.

CLI:  python3 quantum_dynamics.py <delta> <omega> <T>
Prints: a single floating-point number: P1(T) (no trailing text on stdout).
"""
import sys

import numpy as np
import qutip as q


def excited_population(delta, omega, T, n_steps=4000):
    # Build the Hamiltonian and the initial / observable operators with QuTiP.
    H = -0.5 * delta * q.sigmaz() + 0.5 * omega * q.sigmax()
    psi0 = q.basis(2, 0)                      # |0>
    projector = q.basis(2, 1) * q.basis(2, 1).dag()  # |1><1|
    times = np.linspace(0.0, T, n_steps)
    result = q.sesolve(H, psi0, times, e_ops=[projector])
    return float(result.expect[0][-1])


def main():
    if len(sys.argv) != 4:
        print("usage: quantum_dynamics.py <delta> <omega> <T>", file=sys.stderr)
        sys.exit(2)
    delta = float(sys.argv[1])
    omega = float(sys.argv[2])
    T = float(sys.argv[3])
    p1 = excited_population(delta, omega, T)
    print(repr(p1))


if __name__ == "__main__":
    main()
