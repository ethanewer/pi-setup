#!/usr/bin/env python3
"""
Vine Terrace -- canonical reference implementation of /app/analyze.py.

This is the ground-truth implementation used by the grader's oracle and by the
author's own end-to-end validation.  It also documents the exact public API and
output contracts that the task's instruction.md asks the solver to reproduce in
their own /app/analyze.py.

Functions exposed (the contract):
  points_to_histogram(points, box, bins) -> np.ndarray  (shape (ny, nx), sum == 1)
  parse_spectrum(path)                    -> (np.ndarray, np.ndarray)  (x, y)
  minimal_adjustment_sets(graph_path)     -> list[list[str]]
  design_primers(parts_tsv_path)          -> list[dict]
  build_deliverables(parts_tsv, causal_path)  # writes /app/adjust.json, /app/primers.tsv
  class RGCChannels
  membrane_response(swc_path, params_path) -> np.ndarray  (voltage, shape (n, t))

Primer design constants (shared with the grader):
  ANNEAL_MIN=18, ANNEAL_MAX=24, TM_MIN=58.0, TM_MAX=66.0
  PREFIX_F="GTCA", PREFIX_R="TGAC"
  Tm = 2*(A+T) + 4*(G+C)   [Wallace rule on the 3' annealing window]
"""
import itertools
import json
import re
import numpy as np
import jax.numpy as jnp
import jaxley as jx
import jaxley.channels as jxc

ANNEAL_MIN, ANNEAL_MAX = 18, 24
TM_MIN, TM_MAX = 58.0, 66.0
PREFIX_F, PREFIX_R = "GTCA", "TGAC"

# --------------------------------------------------------------------------- #
# Competency A: bin point clouds into a normalized 2-d histogram
# --------------------------------------------------------------------------- #
def points_to_histogram(points, box, bins):
    """Convert 2d points into a size-(ny,nx) grid of in-box counts that sums to 1.

    box = [xmin, xmax, ymin, ymax]; bins = (nx, ny).
    A point counts if xmin <= x <= xmax AND ymin <= y <= ymax.
    The maximum edge is inclusive (a point exactly on xmax / ymax goes into the
    last bin).  If no point is in the box, return an all-zero grid (sum 0).
    """
    xmin, xmax, ymin, ymax = box
    nx, ny = bins
    pts = np.asarray(points, dtype=np.float64)
    if pts.size == 0:
        pts = np.empty((0, 2))
    inb = (
        (pts[:, 0] >= xmin) & (pts[:, 0] <= xmax)
        & (pts[:, 1] >= ymin) & (pts[:, 1] <= ymax)
    )
    sub = pts[inb]
    g = np.zeros((ny, nx), dtype=np.float64)
    if sub.shape[0] == 0:
        return g
    xs = np.clip(sub[:, 0], xmin, xmax - 1e-12)
    ys = np.clip(sub[:, 1], ymin, ymax - 1e-12)
    xi = np.clip(((xs - xmin) / (xmax - xmin) * nx).astype(int), 0, nx - 1)
    yi = np.clip(((ys - ymin) / (ymax - ymin) * ny).astype(int), 0, ny - 1)
    np.add.at(g, (yi, xi), 1)
    return g / g.sum()

# --------------------------------------------------------------------------- #
# Competency B: parse a non-standard delimited spectrum file
# --------------------------------------------------------------------------- #
def parse_spectrum(path):
    """Read a ';'-delimited spectrum whose decimal separator is ','.

    The first two non-comment lines carry the transposed columns: the abscissa
    row then the ordinate row.  Lines beginning with ';' or '#' are ignored.
    Returns (x, y) float arrays of equal length.
    """
    def clean(tok):
        tok = tok.strip()
        if not tok:
            raise ValueError("empty spectrum field")
        return float(tok.replace(",", "."))
    rows = []
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith(";") or line.startswith("#"):
                continue
            rows.append([clean(t) for t in line.split(";")])
    if len(rows) < 2:
        raise ValueError("spectrum file needs an abscissa row and an ordinate row")
    x = np.asarray(rows[0])
    y = np.asarray(rows[1])
    if x.size != y.size:
        raise ValueError("abscissa/ordinate rows have unequal length")
    return x, y

# --------------------------------------------------------------------------- #
# Competency C: parse a causal graph and derive all minimal adjustment sets
# --------------------------------------------------------------------------- #
def _parse_graph(text):
    edges, effect, forbid = [], None, set()
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        if ln.startswith("effect:"):
            effect = tuple(p.strip() for p in ln.split(":")[1].strip().split("->"))
            continue
        if ln.startswith("forbid:"):
            forbid = set(p.strip() for p in ln.split(":")[1].split(",")) - {""}
            continue
        if "->" in ln:
            edges.append(tuple(p.strip() for p in ln.split("->")))
    return edges, effect, forbid

def _maps(edges):
    parents, children, nodes = {}, {}, set()
    for a, b in edges:
        children.setdefault(a, set()).add(b)
        parents.setdefault(b, set()).add(a)
        nodes.add(a); nodes.add(b)
    return parents, children, nodes

def _ancestors(parents, nodes):
    out = set(nodes); stack = list(nodes)
    while stack:
        u = stack.pop()
        for p in parents.get(u, ()):
            if p not in out:
                out.add(p); stack.append(p)
    return out

def _dsep(edges, x, y, z):
    """True if x and y are d-separated given z (moral-graph criterion)."""
    parents, children, _ = _maps(edges)
    A = _ancestors(parents, {x, y} | set(z))
    und = {n: set() for n in A}
    for a, b in edges:
        if a in A and b in A:
            und[a].add(b); und[b].add(a)
    for b in A:
        ps = [p for p in parents.get(b, ()) if p in A]
        for i in range(len(ps)):
            for j in range(i + 1, len(ps)):
                und[ps[i]].add(ps[j]); und[ps[j]].add(ps[i])
    active = A - set(z)
    seen = {x}; stack = [x]
    while stack:
        u = stack.pop()
        for w in und[u]:
            if w in active and w not in seen:
                seen.add(w); stack.append(w)
    return y not in seen

def _descendants(edges, x):
    _, children, _ = _maps(edges)
    des = set(); stack = [x]
    while stack:
        u = stack.pop()
        for w in children.get(u, ()):
            if w not in des:
                des.add(w); stack.append(w)
    return des

def _backdoor_valid(edges, x, y, z, forbid):
    if any(v in {x, y} for v in z) or any(v in forbid for v in z):
        return False
    if any(v in _descendants(edges, x) for v in z):
        return False
    red = [(a, b) for a, b in edges if a != x]   # erase out-edges of the treatment
    return _dsep(red, x, y, set(z))

def minimal_adjustment_sets(graph_path):
    """Return all inclusion-minimal back-door adjustment sets for the effect
    declared in `effect:` (format 'A -> B'), excluding forbidden nodes and
    variables that are descendants of the treatment."""
    with open(graph_path) as fh:
        text = fh.read()
    edges, effect, forbid = _parse_graph(text)
    x, y = effect
    _, _, nodes = _maps(edges)
    others = nodes - {x, y} - forbid
    valid = []
    for r in range(len(others) + 1):
        for z in itertools.combinations(sorted(others), r):
            if _backdoor_valid(edges, x, y, set(z), forbid):
                valid.append(frozenset(z))
    minimal = [z for z in valid if not any(w < z for w in valid)]
    return sorted([sorted(v) for v in minimal], key=lambda s: (len(s), s))

# --------------------------------------------------------------------------- #
# Competency D: design restriction-assembly primer oligos
# --------------------------------------------------------------------------- #
def _revcomp(seq):
    return seq[::-1].translate(str.maketrans("ACGT", "TGCA"))

def _tm(seq):
    return 2 * (seq.count("A") + seq.count("T")) + 4 * (seq.count("G") + seq.count("C"))

def _read_parts(path):
    parts = []
    with open(path) as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {k: i for i, k in enumerate(header)}
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            f = line.split("\t")
            parts.append({
                "part": f[idx["part"]], "prefixF": f[idx["prefixF"]],
                "prefixR": f[idx["prefixR"]], "site": f[idx["site"]],
                "junction": f[idx["junction"]],
                "anneal_min": int(f[idx["anneal_min"]]),
                "anneal_max": int(f[idx["anneal_max"]]),
                "tm_min": float(f[idx["tm_min"]]), "tm_max": float(f[idx["tm_max"]]),
                "flank5": f[idx["flank5_30nt"]], "flank3": f[idx["flank3_30nt"]],
            })
    return parts

def _pick_len(siteseq, lo, hi, tmin, tmax):
    """Smallest L in [lo,hi] whose Wallace Tm of siteseq window is within bounds.
    siteseq already the candidate anneal window family for a given L."""
    for L in range(lo, hi + 1):
        if tmin <= _tm(siteseq(L)) <= tmax:
            return L
    return None

def design_primers(parts_tsv_path):
    """Design forward + reverse primers for every part.  Returns list of dicts."""
    parts = _read_parts(parts_tsv_path)
    out = []
    for p in parts:
        lo, hi = p["anneal_min"], p["anneal_max"]
        tmin, tmax = p["tm_min"], p["tm_max"]
        # forward: overhang prefix + site + junction + last-L bases of flank5
        Lf = _pick_len(lambda L: p["flank5"][-L:], lo, hi, tmin, tmax)
        anneal_f = p["flank5"][-Lf:]
        primer_f = p["prefixF"] + p["site"] + p["junction"] + anneal_f
        # reverse: overhang prefix + rc(site) + rc(junction) + rc(first-L of flank3)
        Lr = _pick_len(lambda L: _revcomp(p["flank3"][:L]), lo, hi, tmin, tmax)
        anneal_r = _revcomp(p["flank3"][:Lr])
        primer_r = p["prefixR"] + _revcomp(p["site"]) + _revcomp(p["junction"]) + anneal_r
        out.append({
            "name": p["part"] + "_F", "seq": primer_f,
            "anneal_len": Lf, "tm": _tm(anneal_f),
            "site": p["site"], "junction": p["junction"],
        })
        out.append({
            "name": p["part"] + "_R", "seq": primer_r,
            "anneal_len": Lr, "tm": _tm(anneal_r),
            "site": _revcomp(p["site"]), "junction": _revcomp(p["junction"]),
        })
    return out

def _write_primers_tsv(parts_tsv_path, out_path):
    primers = design_primers(parts_tsv_path)
    with open(out_path, "w") as fh:
        fh.write("name\tprimer5to3\toverhang_5\tanneal_len\ttm_anneal\tsite\tjunction\n")
        for r in primers:
            ov = len(r["seq"]) - r["anneal_len"]
            fh.write("\t".join([
                r["name"], r["seq"], str(ov), str(r["anneal_len"]),
                f"{r['tm']:.1f}", r["site"], r["junction"],
            ]) + "\n")
    return primers

# --------------------------------------------------------------------------- #
# Competency E: translate neuron biophysics channels into Jaxley
# --------------------------------------------------------------------------- #
class Naf(jxc.Channel):
    """Fast sodium (m^3 h) ported from rgc.mod -> jaxley."""
    def __init__(self, g=120e-3, e=55.0, name="j_naf"):
        self.current_is_in_mA_per_cm2 = True
        super().__init__(name)
        self.channel_params = {"g_na": g, "e_na": e}
        self.channel_states = {"m": 0.05, "h": 0.6}
        self.current_name = "i_naf"
    def _rates(self, v):
        vm = v + 40.0
        am = jnp.where(jnp.abs(vm) < 1e-8, 1.0, vm / (1.0 - jnp.exp(-vm / 10.0)))
        bm = 4.0 * jnp.exp(-(v + 65.0) / 18.0)
        ah = 0.07 * jnp.exp(-(v + 65.0) / 20.0)
        bh = 1.0 / (1.0 + jnp.exp(-(v + 35.0) / 10.0))
        return am, bm, ah, bh
    def update_states(self, states, delta_t, v, params):
        am, bm, ah, bh = self._rates(v)
        tm, m_inf = 1.0 / (am + bm), am / (am + bm)
        th, h_inf = 1.0 / (ah + bh), ah / (ah + bh)
        return {"m": m_inf + (states["m"] - m_inf) * jnp.exp(-delta_t / tm),
                "h": h_inf + (states["h"] - h_inf) * jnp.exp(-delta_t / th)}
    def compute_current(self, states, v, params):
        return params["g_na"] * states["m"] ** 3 * states["h"] * (v - params["e_na"])

class Kd(jxc.Channel):
    def __init__(self, g=36e-3, e=-90.0, name="j_kd"):
        self.current_is_in_mA_per_cm2 = True
        super().__init__(name)
        self.channel_params = {"g_k": g, "e_k": e}
        self.channel_states = {"n": 0.3}
        self.current_name = "i_kd"
    def _rates(self, v):
        vn = v + 55.0
        an = jnp.where(jnp.abs(vn) < 1e-8, 0.1, 0.01 * vn / (1.0 - jnp.exp(-vn / 10.0)))
        bn = 0.125 * jnp.exp(-(v + 65.0) / 80.0)
        return an, bn
    def update_states(self, states, delta_t, v, params):
        an, bn = self._rates(v)
        tau, n_inf = 1.0 / (an + bn), an / (an + bn)
        return {"n": n_inf + (states["n"] - n_inf) * jnp.exp(-delta_t / tau)}
    def compute_current(self, states, v, params):
        return params["g_k"] * states["n"] ** 4 * (v - params["e_k"])

class Leak(jxc.Channel):
    def __init__(self, g=0.3e-3, e=-65.0, name="j_leak"):
        self.current_is_in_mA_per_cm2 = True
        super().__init__(name)
        self.channel_params = {"g_l": g, "e_l": e}
        self.channel_states = {}
        self.current_name = "i_leak"
    def update_states(self, states, delta_t, v, params):
        return states
    def compute_current(self, states, v, params):
        return params["g_l"] * (v - params["e_l"])

class RGCChannels:
    """Conversion class: attach the three ported RGC channels to a morphology."""
    def __init__(self, params):
        self.params = params
    def add_channels(self, cell):
        cell.insert(Naf(g=self.params.get("g_na", 120e-3), e=self.params.get("e_na", 55.0)))
        cell.insert(Kd(g=self.params.get("g_k", 36e-3), e=self.params.get("e_k", -90.0)))
        cell.insert(Leak(g=self.params.get("g_leak", 0.3e-3), e=self.params.get("e_leak", -65.0)))
        return cell

def membrane_response(swc_path, params_path, t_ms=None, delta_t=None):
    """Load the morphology, attach the RGC channels, stimulate and integrate.

    Returns the voltage array with shape (n_compartment, n_steps).
    """
    with open(params_path) as fh:
        pm = json.load(fh)
    t_ms = t_ms if t_ms is not None else pm.get("t_ms", 60.0)
    delta_t = delta_t if delta_t is not None else pm.get("delta_t", 0.025)
    cell = jx.read_swc(swc_path, ncomp=1)
    RGCChannels(pm).add_channels(cell)
    net = jx.Network([cell])
    t = np.arange(0.0, t_ms, delta_t)
    cur = np.where((t >= 2.0) & (t <= 22.0), pm.get("stim_nA", 0.9), 0.0)
    net.stimulate(current=cur)
    net.record(state="v")
    return jx.integrate(net, t_max=t_ms, delta_t=delta_t)

# --------------------------------------------------------------------------- #
# deliverable production
# --------------------------------------------------------------------------- #
def build_deliverables(parts_tsv="/app/primer/parts.tsv",
                       causal_path="/app/causal/graphA.txt"):
    _write_primers_tsv(parts_tsv, "/app/primers.tsv")
    sets = minimal_adjustment_sets(causal_path)
    with open("/app/adjust.json", "w") as fh:
        json.dump(sets, fh, indent=1)
    return sets

if __name__ == "__main__":
    build_deliverables()
    print("wrote /app/primers.tsv and /app/adjust.json")
