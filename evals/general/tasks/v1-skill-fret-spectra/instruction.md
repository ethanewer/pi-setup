You are analyzing a **FRET (Förster resonance energy transfer)** pair. In FRET, donor and acceptor spectra must overlap for efficient energy transfer. Two quantities are computed from measured donor lifetimes.

In `/app/data.json` there is:
```json
{"tau_D": 4.5, "tau_DA": 2.7}
```
where:
- `tau_D` is the donor lifetime (ns) measured **without** the acceptor.
- `tau_DA` is the donor lifetime (ns) measured in presence of the acceptor.

The **FRET efficiency** is:
```
E = 1 - (tau_DA / tau_D)
```

Write `/app/fret.py` that computes `E` and writes `/app/fret_efficiency.json` containing exactly:
```json
{"E": <value rounded to 4 decimals>}
```

Run your script so `/app/fret_efficiency.json` has the correct value. Use `python3`.