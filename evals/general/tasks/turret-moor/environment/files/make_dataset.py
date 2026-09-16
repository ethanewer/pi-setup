"""Author the pluto-format (boxlib) simulation snapshot fixtures for the
turret-moor task.

This is our own authored generator: it writes an AMReX "pluto" plotfile
directory (the text ``Header`` plus ``Level_0/CellData_H`` and the binary
``Level_0/CellData`` layout read by yt's boxlib frontend), along with a
``source.npz`` holding the raw arrays used to sanity-check the verifier.

The fixture is a single-grid, single-level, non-periodic snapshot of a
mock radiation-hydrodynamics blob: a cold, dense core surrounded by hot,
diffuse gas hosting small temperature/density fluctuations.

Usage:
    python3 make_dataset.py <out-dir> [--seed N] [--N nx ny nz]
        [--box lo hi] [--rcore R] [--peak P] [--floor F] [--tcore T]
        [--tiso A] [--noise S]
"""

import argparse
import os

import numpy as np


def make_dataset(outdir, seed, N, box, rcore, peak, floor, tcore, tiso, noise_sigma):
    rng = np.random.default_rng(seed)
    nx, ny, nz = N
    xlo, xhi = box
    L = xhi - xlo
    xs = np.linspace(xlo, xhi, nx + 1)
    ys = np.linspace(xlo, xhi, ny + 1)
    zs = np.linspace(xlo, xhi, nz + 1)
    dx = (xs[1] - xs[0]).item()
    dy = (ys[1] - ys[0]).item()
    dz = (zs[1] - zs[0]).item()
    Xc = 0.5 * (xs[1:] + xs[:-1])
    Yc = 0.5 * (ys[1:] + ys[:-1])
    Zc = 0.5 * (zs[1:] + zs[:-1])
    X, Y, Z = np.meshgrid(Xc, Yc, Zc, indexing="ij")
    R = np.sqrt(
        ((X - 0.5 * (xlo + xhi)) / L) ** 2
        + ((Y - 0.5 * (xlo + xhi)) / L) ** 2
        + ((Z - 0.5 * (xlo + xhi)) / L) ** 2
    )
    # density: concentrated core plus a diffuse halo and small fluctuations
    density = peak * np.exp(-(R / rcore) ** 2) + floor
    density = density * (1.0 + 0.35 * rng.normal(size=R.shape))
    density = np.clip(density, 1.0e-24, None)
    # temperature: hot halo anticorrelated with density, with its own noise
    temperature = tcore * (1.0 + tiso * (R / rcore) ** 2)
    temperature = temperature * (1.0 + noise_sigma * rng.normal(size=R.shape))
    temperature = np.clip(temperature, 1.0e3, None)

    sim = os.path.join(outdir, "sim")
    os.makedirs(os.path.join(sim, "Level_0"), exist_ok=True)

    header = [
        "1.0",
        "2",
        "density",
        "temperature",
        "3",
        "0.0",
        "0",
        f"{xlo} {xlo} {xlo}",
        f"{xhi} {xhi} {xhi}",
        "1",
        f"((0,0,0) ({nx-1},{ny-1},{nz-1}) (0,0,0))",
        "1",
        f"{dx} {dy} {dz}",
        "0",
        "0",
        "0 1 1",
        "1",
        f"{xlo} {xhi}",
        f"{xlo} {xhi}",
        f"{xlo} {xhi}",
        "Level_0/CellData",
    ]
    with open(os.path.join(sim, "Header"), "w") as f:
        f.write("\n".join(header) + "\n")

    level_header = [
        "T_0.0.0_2.0.0_2.0.0_0",
        "write_pluto",
        "2",
        "0",
        "(1 0",
        f"((0,0,0) ({nx-1},{ny-1},{nz-1}) (0,0,0))",
        ")",
        "1",
        "0 CellData 0",
    ]
    with open(os.path.join(sim, "Level_0", "CellData_H"), "w") as f:
        f.write("\n".join(level_header) + "\n")

    fab = (
        f"FAB ((8, (64 11 52 0 1 12 0 1023)),(8, (8 7 6 5 4 3 2 1)))"
        f"((0,0,0) ({nx-1},{ny-1},{nz-1}) (0,0,0)) 2\n"
    )
    with open(os.path.join(sim, "Level_0", "CellData"), "wb") as f:
        f.write(fab.encode("ascii"))
        for arr in (density, temperature):
            f.write(np.ascontiguousarray(arr.ravel(order="F"), dtype="<f8").tobytes())

    np.savez(
        os.path.join(outdir, "source.npz"),
        density=density,
        temperature=temperature,
        N=np.array(N),
        box=np.array(box),
    )
    return os.path.join(sim)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--N", type=int, nargs=3, default=[32, 32, 32])
    ap.add_argument("--box", type=float, nargs=2, default=[0.0, 3.2e17])
    ap.add_argument("--rcore", type=float, default=0.35)
    ap.add_argument("--peak", type=float, default=2.0e-20)
    ap.add_argument("--floor", type=float, default=5.0e-22)
    ap.add_argument("--tcore", type=float, default=3.0e6)
    ap.add_argument("--tiso", type=float, default=6.0)
    ap.add_argument("--noise", type=float, default=0.2)
    args = ap.parse_args()
    path = make_dataset(
        args.out_dir,
        args.seed,
        tuple(args.N),
        tuple(args.box),
        args.rcore,
        args.peak,
        args.floor,
        args.tcore,
        args.tiso,
        args.noise,
    )
    print("wrote", path)


if __name__ == "__main__":
    main()