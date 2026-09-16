# Turret-moor: real scientific analysis inside a real astrophysics codebase

## Scenario

You are working with the yt analysis toolkit, a real open-source project for
scientific visualization and analysis of volumetric data. A pinned checkout of
the upstream repository is installed at `/app/src` (release 4.4.2, commit
f043ac8). The package has been installed **from that very checkout** in
editable mode: `import yt` loads the code in `/app/src/yt`, including its
compiled extensions. Read any part of the tree you need — `yt/frontends/`,
`doc/`, the test suite — the codebase is there to be used and understood.

A simulation snapshot is on disk at `/app/data/sim`. It is a single-level,
single-grid output directory written in the "pluto" plotfile format of the
boxlib AMR framework (the format produced by the Castro and MAESTRO
radiation-hydrodynamics codes, supported by yt's boxlib frontend). The
directory contains a text `Header` file and binary field data under
`Level_0/`. It is a snapshot of a 3-D gas blob: a cold dense core surrounded by
hot, diffuse gas with small fluctuations. The simulation domain is Cartesian
and uniform, with physical coordinates in centimeters. The two fields stored
per cell are `density` (mass density, g/cm^3) and `temperature` (K).
`/app/make_dataset.py` is the script that generated this snapshot; you may
inspect it to understand the dataset, and generate your own test snapshots
with it if you like.

## Task

Write a Python analysis program at **`/app/analyze.py`** that:

1. Takes two command-line arguments: a dataset directory and an output path.
   ```
   python3 /app/analyze.py <dataset-dir> <output.json>
   ```
   The dataset directory is one that directly contains a file named `Header`
   (like `/app/data/sim`).
2. Loads the dataset with **yt's own loading machinery** — the analysis must
   go through yt's dataset object, using its field system and its derived
   quantities, not through a hand-rolled parser of the raw files. The whole
   point of this task is that the work happens inside the yt library.
3. Computes, for the whole domain:
   - the **total mass** of the gas in grams,
   - the **mass-weighted (density-weighted) mean temperature** in kelvin,
   - the **number of simulation cells**.
4. Writes the output JSON file with exactly these keys, in any order:

   ```json
   {
     "total_mass_g": 1.23e32,
     "mass_weighted_temperature_K": 2.5e7,
     "cell_count": 32768
   }
   ```

5. Run your program on the visible dataset and leave the result at
   **`/app/answer.json`** (i.e. `python3 /app/analyze.py /app/data/sim
   /app/answer.json`), so your script and its output are both on disk.

## Constraints

- Use yt's API for the loading and the derived quantities. A solution that
  parses the binary field files with numpy directly, bypassing yt, does not
  satisfy the task even if the numbers come out right.
- Do not hardcode values: your program must work for any dataset directory of
  this format, including ones you have never seen (different grid sizes,
  different domain extents, different fields values).
- Every needed package is already installed. There is no network at run time:
  do not fetch anything.
- You do not need to modify anything under `/app/src`. You may read it as much
  as you like. Leave other files under `/app` alone except for creating
  `/app/analyze.py` and `/app/answer.json`.

## Grading

Your output is scored on the visible fixture and on three hidden snapshots of
the same format (same fields, different grids and physical parameters). For
each snapshot your `analyze.py` is run with that dataset directory and its
reported floats are compared against independently computed values (a plain
numpy evaluation of the same physical integrals) to a relative tolerance of
1e-3, with `cell_count` matched exactly. The grader also asserts that `import
yt` resolves to the `/app/src` checkout and that your program actually loads
the data through yt.