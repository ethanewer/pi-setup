# drift-atlas — simulation-studio authoring bench

You are setting up a small simulation studio in `/app`. Five independent jobs
must be finished, and every result must be a real, checked artifact at a
literal `/app` path. Read the whole contract before starting — each subsection
tells you exactly how the artifact will be re-executed and what is probed.

A populated fixture set already lives in `/app`:

- `/app/morphology.json`, `/app/stimulus.json` — neuron job inputs
- `/app/sample_smiles.txt` — one SMILES per line (molecular-descriptor job)
- `/app/ref-model.xml` — the MuJoCo reference model (**must not change**)
- `/app/corewar/` — the Atlas-Red engine (`core.py`), the tournament holdouts
  (`opponents/*.red`) and a `starter.red` skeleton (**do not modify the engine
  or the holdouts**; write your own warrior elsewhere)

Do **not** modify, rename or delete any shipped fixture. Everything you produce
that is checked lives at the eleven deliverable paths listed in Deliverables
(section 0).

---

## 0. Deliverables to produce in /app

| # | path                          | written by you |
|---|-------------------------------|----------------|
| 1 | `/app/channels.py`            | author        |
| 2 | `/app/neuron.py`              | author        |
| 3 | `/app/spike-trace.json`       | run neuron.py |
| 4 | `/app/descriptors.py`         | author        |
| 5 | `/app/descriptors.json`       | run descriptors.py |
| 6 | `/app/ref-model.xml`          | untouched fixture |
| 7 | `/app/tuned-model.xml`        | tune ref-model |
| 8 | `/app/mujoco-load.txt`        | proof of step |
| 9 | `/app/warrior.red`            | author        |
| 10| `/app/tournament.json`        | run the engine |
| 11| `/app/sizes.json`             | measure sizes |

All Python files must run under the image's `python3` (3.12). `numpy`,
`scipy`, `rdkit` and `mujoco` are preinstalled. The verifier **re-executes**
these artifacts on inputs it holds (see each section), so nothing may be
hard-coded for the shipped fixtures.

---

## 1. Neuron job — `/app/channels.py`, `/app/neuron.py`, `/app/spike-trace.json`

### 1.1 The biophysics contract (implement exactly)

Potentials are in **mV**, time in **ms**, conductances in **microSiemens
(uS)**, capacitances in **nanoFarads (nF)**, currents in **nanoAmperes (nA)**.
With these units `current(uS)·potential(mV)` yields nA and
`current(nA)/capacitance(nF)` yields `mV/ms`.

Each compartment `j` obeys

```
I_memb,j = gNa_j·m_j³·h_j·(V_j - Ena_j) + gK_j·n_j⁴·(V_j - Ek_j) + gL_j·(V_j - Eleak_j)
I_cable,j = Σ_c  gS_c·(V_neighbour - V_j)        # over cable edges (see below)
dV_j/dt = ( I_stim_j − I_memb,j + I_cable,j ) / C_j
```

Gating variables follow Hodgkin-Huxley kinetics with these exact rate
functions:

```
alpha_m(v) = 0.1·(v+40) / (1 − exp(−(v+40)/10))     (limit 1.0 at v = −40)
beta_m(v)  = 4·exp(−(v+65)/18)
alpha_h(v) = 0.07·exp(−(v+65)/20)
beta_h(v)  = 1 / (1 + exp(−(v+35)/10))
alpha_n(v) = 0.01·(v+55) / (1 − exp(−(v+55)/10))    (limit 0.1 at v = −55)
beta_n(v)  = 0.125·exp(−(v+65)/80)

dm/dt = alpha_m(V)·(1−m) − beta_m(V)·m      (analogous for h and n)
```

Initial condition in every compartment: `(m,h,n)` set to the steady state at
the compartment's `v0`, i.e. `m = alpha_m(v0)/(alpha_m(v0)+beta_m(v0))`, and
similarly for `h` and `n` (a zero/zero division at that single point counts as
0 for that gate).

Numerics: fixed-step **explicit Euler** with the step `dt` taken from the
morphology. Per time step, in this order:

1. advance every gate using the *current* `V` (before the update);
2. evaluate `I_memb` and `I_cable` using the *old* `V` and the *updated*
   gates; add the stimulus to the soma; store `dV/dt` per compartment;
3. update every `V` by `dt·(dV/dt)`.

A **spike** occurs on the soma when the previous step's soma potential `≤ 20`
and the current step's `> 20`; record the crossing time rounded to 4 decimals
as `t − dt/2`.

### 1.2 morphology.json / stimulus.json format

```json
{
  "dt": 0.01, "tmax": 40.0, "soma": "soma",
  "compartments": [
    {"name": "soma", "C": 1.0, "gNa": 120.0, "gK": 36.0, "gL": 0.3,
     "Ena": 55.0, "Ek": -77.0, "Eleak": -54.4, "v0": -65.0},
    {"name": "spind", "parent": "soma", "gS": 0.5, "C": 1.0, ...}
  ]
}
```

- `soma` names the compartment whose potential is recorded.
- Every compartment needs `C, gNa, gK, gL, Ena, Ek, Eleak` (and optional
  `v0`, default −65). They must be read as floats even if written as ints.
- **Cable edges**: a compartment whose `parent` names a compartment that *is*
  present in the list is connected to that parent by a symmetric series
  conductance `gS` (uS, default 0). A compartment whose `parent` names a
  compartment that is **not** present is treated as an **isolated root**: it
  participates in the simulation but has **no** cable edges. `parent`/`gS`
  are optional (absent = no edge). Nodes may form a chain or a small tree;
  traversal order = the order compartments appear in the list.
- `dt` may vary (smaller steps give smoother traces); `tmax` is the simulated
  duration. The number of steps is `round(tmax/dt)`.

```json
{"start": 2.0, "duration": 36.0, "amplitude": 9.0}
```

- A constant current `amplitude` (nA, may be **negative** for a
  hyperpolarizing pulse) is applied to the soma while `start ≤ t < start +
  duration`. Outside the window the stimulus is 0.00.

### 1.3 CLI and output

```
python3 /app/neuron.py <morphology.json> <stimulus.json> <output.json>
```

Writes `output.json` (compact JSON, keys in this order):

```json
{"dt": 0.01, "tmax": 40.0, "v": [ ... soma V per step ... ], "spikes": [ ... ]}
```

Produce the deliverable by running:

```
python3 /app/neuron.py /app/morphology.json /app/stimulus.json /app/spike-trace.json
```

### 1.4 channels.py contract

`/app/channels.py` must expose the six rate functions above
(`alpha_m, beta_m, alpha_h, beta_h, alpha_n, beta_n`), a `steady_gates(v)`
helper returning `(m,h,n)` steady state, and three classes named
`Sodium`, `Potassium`, `Leak` with gating exponents
`Sodium.exp == {"m":3,"h":1}`, `Potassium.exp == {"n":4}`,
`Leak.exp == {}`. `neuron.py` is expected to drive the morphology through
these gating constants; the verifier re-checks the constants independently.

### 1.5 Hidden probing (generalize, do not hard-code)

The verifier re-runs your `neuron.py` on the shipped morphology and on several
**hidden** morphology/stimulus pairs and compares the whole soma trace and
spike list to an independent implementation of the exact contract above. The
hidden pairs include: a multi-branch cell that fires several spikes; a
**single-compartment** cell (no cable at all) under a weak stimulus (no
spikes); a compact cell containing an **isolated compartment** whose `parent`
does not exist, driven by a **negative-amplitude** (hyperpolarizing) pulse
(no spikes). Traces must match within 0.05 mV absolute (or 2% relative,
whichever is larger), spike counts exactly, each spike time within 0.15 ms.

---

## 2. Molecular descriptors — `/app/descriptors.py`, `/app/descriptors.json`

Write `descriptors.py` with `compute(smiles)` that returns a dict with
**exactly** these keys and **exactly** these Python types (derive every value
from RDKit — no hard-coding):

```python
{"smiles": str, "logp": float, "mw": float, "hbd": int,
 "hba": int, "rotb": int, "tpsa": float}
```

- `logp` = `Crippen.MolLogP`, `mw` = `rdMolDescriptors.CalcExactMolWt`,
  `hbd`/`hba` = `CalcNumHBD`/`CalcNumHBA`, `rotb` =
  `CalcNumRotatableBonds`, `tpsa` = `CalcTPSA` (ints cast with `int(...)`,
  floats cast with `float(...)`).
- For a SMILES RDKit cannot parse, return
  `{"smiles": <input>, "error": "invalid smiles"}`.
- An **empty string is a valid molecule** for RDKit (the empty mol): return
  the zero/zero dictionary with `tpsa` as the float `0.0`, not int `0`.

CLI:

```
python3 /app/descriptors.py --compute <smiles>     # prints ONE JSON line
python3 /app/descriptors.py --write <smiles.txt> <out.json>
```

`--write` reads whitespace-trimmed non-empty lines and writes
`{"source": "<txt>", "molecules": [ ...compute() dict, in file order... ]}`.

Produce the deliverable with:

```
python3 /app/descriptors.py --write /app/sample_smiles.txt /app/descriptors.json
```

Hidden probing: the verifier re-runs `--compute` on hidden molecule sets
(valid organics with zero-count fields `hbd/hba/rotb = 0` as **ints** vs
`tpsa = 0.0` as a **float**, ring systems, and deliberately **invalid**
SMILES strings) and type-checks **every** value plus its Python type against
an independent RDKit recomputation. A wrong type (e.g. `mw` as int, `hbd` as
float, `tpsa` as int 0) fails. Whitespace around a molecule is trimmed.

---

## 3. MuJoCo tuning — `/app/ref-model.xml`, `/app/tuned-model.xml`, `/app/mujoco-load.txt`

`/app/ref-model.xml` is a single self-contained MJCF (a pivoting arm with one
hinge `shoulder`, one `motor` actuator with `gear="0.07"`, no assets, no
plugins). Your job: **tune** it into `/app/tuned-model.xml` so the model can
be made to sweep, then prove it under a clean MuJoCo install.

Acceptance the verifier applies (it runs this itself, plugin-free, CPU only):

- `/app/ref-model.xml` must remain **byte-identical** to the shipped original
  (it is compared to a pristine copy). Never overwrite it.
- `/app/tuned-model.xml` must differ from the reference, must load with
  `mujoco.MjModel.from_xml_path` **without any plugins or extra asset files**,
  and when stepped with `d.ctrl[0] = 2.0` at the model's default timestep
  for **2.0 s** the shoulder joint must sweep to `|q[0]| > 1.1 rad` at some
  point (the arm rotates out of its rest). The pristine reference under the
  same 2 s / ctrl=2.0 drive stays **below** 1.1 rad.
- `/app/mujoco-load.txt` must be non-empty and its first line must start with
  the token `MUJOCO_OK`. Write the sweep result you observed there, e.g.
  `MUJOCO_OK tuned=atlas-gain freq=0 plugins=0 sweep=1.844`.

A standard `python3 -c "import mujoco"` then `mj_step` loop is all the launcher
you need. Keep the model a single self-contained XML (no meshes, no extra
files) so it loads anywhere.

---

## 4. Atlas-Red tournament — `/app/warrior.red`, `/app/tournament.json`

`/app/corewar/core.py` is a small deterministic **redcode** MARS
(no randomness; `CORE=1024` cells, processes, owned-cell tie-break). Read its
module docstring — it is the authority on the instruction set:

```
Instruction:  OP [A] [B]        A,B are signed cell offsets
              OP in { DAT MOV ADD SUB JMP JMZ DJZ SPL }
              a '#' prefix on an operand makes it an immediate literal
              ';' starts a comment
```

- `DAT` kills the executing process.
- `MOV A B` copies the whole cell at `PC+A` into `PC+B` (an immediate `A`
  writes a literal `DAT` bomb instead).
- `ADD/SUB A B` add/subtract a value to the `A`-field of the cell at `PC+B`.
- `JMP A` jumps `PC+A`; `JMZ A B` (and `DJZ A B`) jump when a test is zero.
- `SPL A` forks an extra process at `PC+A` (this is how a warrior grows).

Run the tournament for your warrior with:

```
python3 /app/corewar/core.py /app/warrior.red
```

It prints, for `/app/corewar/opponents/*.red`, one result per holdout with a
`winner` (1 = you, 2 = opponent, 0 = tie). Your `warrior.red` must win **every
round**. The shipped `starter.red` (a `JMP 0` hop) demonstrably loses, so edit
and iterate until `all_wins: true`. A syntactically valid self-replicating
"worm" that keeps refreshing itself and splitting is one reliable route. Empty
or malformed warriors (only comments, an unknown opcode, a bare `DAT`) have
their process die immediately and lose every round.

Then produce:

```
python3 - <<'PY'
import json, sys
sys.path.insert(0, "/app/corewar")
import core
json.dump(core.tournament("/app/warrior.red", "/app/corewar/opponents"),
          open("/app/tournament.json", "w"), indent=2)
PY
```

`tournament.json` must contain the `rounds` list (opponent file name, `winner`,
`warrior_wins`) and `all_wins`. The verifier re-runs the identical tournament
with the **pristine** engine copy and requires `all_wins` plus agreement
between `tournament.json` and its own recomputation. It also verifies
`/app/corewar/core.py` and the holdout files are byte-identical to the shipped
originals — do not touch them.

---

## 5. sizes.json

Every deliverable sits inside a documented byte ceiling. Produce
`/app/sizes.json` as:

```json
{"artifacts": [ {"path": "/app/neuron.py", "bytes": <int>, "limit": 20000}, ... ]}
```

Covers exactly these eleven paths with these ceilings:

| path                    | limit   |
|-------------------------|---------|
| `/app/neuron.py`        | 20000   |
| `/app/channels.py`      | 12000   |
| `/app/spike-trace.json` | 700000  |
| `/app/descriptors.py`   | 20000   |
| `/app/descriptors.json` | 20000   |
| `/app/ref-model.xml`    | 4000    |
| `/app/tuned-model.xml`  | 4000    |
| `/app/mujoco-load.txt`  | 4000    |
| `/app/warrior.red`      | 4000    |
| `/app/tournament.json`  | 20000   |
| `/app/sizes.json`       | 6000    |

Each `bytes` field must equal the file's real size on disk (for `sizes.json`
itself, record its own serialized byte length after writing). The verifier
re-measures every file byte-for-byte: a mismatch between your reported `bytes`
and the real size, or any size over its ceiling, fails this section.

---

## 6. Pass conditions recap

1. `neuron.py` reproduces the reference trace + spikes for the shipped job and
   every hidden morphology/stimulus; `channels.py` carries the exact gating
   constants/classes.
2. `descriptors.py` returns typed, RDKit-exact descriptors for every hidden
   molecule and the sample list; invalid SMILES handled.
3. `ref-model.xml` byte-identical; `tuned-model.xml` loads & sweeps > 1.1 rad
   (2 s, ctrl=2.0) under clean MuJoCo while the reference stays below;
   `mujoco-load.txt` starts with `MUJOCO_OK`.
4. `warrior.red` wins every Atlas-Red round; `tournament.json` agrees; engine
   and holdouts untouched.
5. All eleven deliverable sizes are real and within their ceilings in
   `sizes.json`.

When in doubt, run the tools yourself in the container: `python3`
`/app/neuron.py`, `/app/descriptors.py`, `/app/corewar/core.py` and a plain
`mujoco` step loop all behave exactly as the verifier will use them.
