#!/usr/bin/env python3
"""Current naive trainer (broken scaffold). Hard-coded paths, no sign
constraint, no experiment-data directory, no held-out accuracy gate."""
import argparse, joblib, pandas as pd
from sklearn.linear_model import LogisticRegression


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="/app/data/company.csv")
    ap.add_argument("--model", default="/app/model.joblib")
    ap.add_argument("--iters", type=int, default=2000)
    args = ap.parse_args()

    df = pd.read_csv(args.data)
    y = df["broke_down"].to_numpy()
    X = df.drop(columns=["broke_down"])
    m = LogisticRegression(max_iter=args.iters)
    m.fit(X, y)
    joblib.dump(m, args.model)
    print("trained (no sign check, no vector, no experiment dir)")


if __name__ == "__main__":
    main()