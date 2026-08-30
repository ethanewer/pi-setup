"""solve_mip.py -- optimize a minimization MPS model (LP, MILP) and report the
objective and the value of every column.

Usage:  python3 /app/solve_mip.py <MODEL.mps> <OUT.json>

Writes <OUT.json>:
    {
      "optimal": true,
      "objective": <float>,
      "x": { "<column-name>": <value>, ... },
      "ncols": <int>,
      "nrows": <int>
    }

The model is a STANDARD minimization MPS file.  Column bounds, integer/continuous
types and row bounds come straight from the MPS sections; the column values are
the primal values produced by the solver.
"""
import sys
import json
import highspy


def solve(model_path, out_path):
    hs = highspy.Highs()
    hs.setOptionValue("output_flag", False)
    if not hs.silent():      # no-op guard for older bindings
        pass
    hs.setOptionValue("log_to_console", False)
    if not hs.readModel(model_path):
        raise RuntimeError(f"failed to read MPS model: {model_path}")
    hs.run()
    status = hs.modelStatusToString(hs.getModelStatus())
    info = hs.getInfo()
    lp = hs.getLp()
    sol = hs.getSolution()

    names = list(lp.col_names_)
    values = [float(v) for v in sol.col_value]
    if len(names) != len(values):
        names = [f"x{i}" for i in range(len(values))]

    result = {
        "optimal": status == "Optimal",
        "status": status,
        "objective": None if status != "Optimal" else float(info.objective_function_value),
        "x": dict(zip(names, values)),
        "ncols": int(lp.num_col_),
        "nrows": int(lp.num_row_),
    }
    with open(out_path, "w") as fh:
        json.dump(result, fh, indent=2)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: solve_mip.py <MODEL.mps> <OUT.json>\n")
        sys.exit(2)
    solve(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    import sys
    main()