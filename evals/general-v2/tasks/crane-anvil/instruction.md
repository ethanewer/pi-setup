# crane-anvil — Torrigan Snow Survey build

The **Torrigan Snow Survey** needs its avalanche-station reporting tool built.
The two Fortran sources and the station data are already in the image; the
build is missing entirely and you must author it. Work under `/app`. Do **not**
modify anything in `/app/sources/` or `/app/data/` (locked survey inputs).

## Provided inputs (read-only)

- `/app/sources/snowmod.f90` — Fortran **module** `snowmod` with three
  procedures: `count_above(vals, n, thresh)`, `mean_val(vals, n)`,
  `peak_val(vals, n)`.
- `/app/sources/avalanche_report.f90` — the main **program** `avalanche_report`,
  which `USE`s module `snowmod` (so it cannot compile until the module has been
  compiled).
- `/app/data/ridgeline.dat` — a station data file: first line is the count `n`,
  second line is `n` real readings.
- `gfortran` and `make` are installed.

## Deliverables (both required)

### 1. `/app/Makefile`

Author a Makefile at exactly `/app/Makefile` that:

- builds the native executable `/app/avalanche_report` from the two sources,
  driving the **`gfortran`** frontend;
- compiles `/app/sources/snowmod.f90` **before**
  `/app/sources/avalanche_report.f90` (the module file `snowmod.mod` must exist
  before the program source is compiled — a wrong ordering fails the build);
- links both object files into `/app/avalanche_report`;
- works when invoked from `/app` as `make -f Makefile` **and** when forced to
  fully rebuild with `make -B -f Makefile` (the verifier always rebuilds with
  `-B` and requires `gfortran` to appear in the compile log).

### 2. `/app/avalanche_report`

The built executable. Interface:

```
/app/avalanche_report <datafile> <threshold>
```

It reads the data file and prints **exactly four lines** (this behavior is
already implemented in the locked source — just build it):

```
n=<count of readings>
warm=<readings strictly greater than threshold>
mean=<arithmetic mean of the readings, 2 decimals>
peak=<maximum reading, 2 decimals>
```

On the shipped visible data:

```
/app/avalanche_report /app/data/ridgeline.dat 2.0
```

must print (leading spaces after `mean=` / `peak=` are fine):

```
n=8
warm=5
mean=4.03
peak=12.50
```

Build it and run this check yourself before finishing.

## How the verifier grades

1. It runs `make -B -f Makefile` in `/app` and requires the build to succeed
   with `gfortran` in the compile log (so the Makefile must really drive
   gfortran, including the module-before-program ordering).
2. It runs `/app/avalanche_report /app/data/ridgeline.dat 2.0` and checks the
   four values.
3. It runs the same executable on **hidden** station data files (different `n`,
   readings, thresholds) and checks the four values against independently
   computed references. The values are parsed numerically, so spacing is free,
   but the `n=`/`warm=`/`mean=`/`peak=` prefixes must appear.

A build that never compiles the module first, or that never links the objects
(e.g. only syntax-checking sources), fails these checks — there is no way to
satisfy them without a real module-then-program gfortran build.

## Constraints

- Deterministic offline build; no network.
- Do not modify `/app/sources/` or `/app/data/`.
