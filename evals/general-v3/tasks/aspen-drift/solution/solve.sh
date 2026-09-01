#!/bin/bash
# Oracle for aspen-drift: write the trainer and evaluator, RUN the trainer on
# the visible training set to produce a real /app/model.pt, then RUN the
# evaluator on the visible holdout to produce /app/predictions.txt.
# Never reads /tests.
set -eu

cat > /app/train_model.py <<'PY'
import sys

import pandas as pd
import torch

FEATURES = [f"x{i}" for i in range(6)]


def build_model():
    return torch.nn.Sequential(
        torch.nn.Linear(6, 24),
        torch.nn.Tanh(),
        torch.nn.Linear(24, 1),
    )


def load_train(path):
    try:
        df = pd.read_csv(path)
    except Exception as e:
        raise ValueError(f"unreadable CSV: {e}")
    need = FEATURES + ["target"]
    missing = [c for c in need if c not in df.columns]
    if missing:
        raise ValueError(f"missing columns: {missing}")
    if len(df) == 0:
        raise ValueError("no data rows")
    try:
        X = df[FEATURES].astype(float).to_numpy()
        y = df["target"].astype(float).to_numpy()
    except Exception as e:
        raise ValueError(f"malformed numeric value: {e}")
    return X, y


def main():
    if len(sys.argv) != 3:
        print("usage: train_model.py <train_csv> <out_snapshot.pt>",
              file=sys.stderr)
        return 2
    train_csv, out_pt = sys.argv[1], sys.argv[2]

    try:
        X, y = load_train(train_csv)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    torch.manual_seed(0)
    torch.set_num_threads(1)

    # Train on standardized inputs (helps the tanh net converge quickly),
    # then bake the standardization into the first Linear layer so the saved
    # state_dict works directly on raw sensor values.
    mu = X.mean(axis=0)
    sd = X.std(axis=0)
    sd[sd == 0] = 1.0
    Xn = (X - mu) / sd

    model = build_model()
    opt = torch.optim.Adam(model.parameters(), lr=2e-2)
    Xn_t = torch.tensor(Xn, dtype=torch.float32)
    y_t = torch.tensor(y, dtype=torch.float32).unsqueeze(1)
    n = len(Xn_t)
    bs = 8
    gen = torch.Generator().manual_seed(1234)
    epochs = 28  # strictly fewer than 30
    model.train()
    for _ in range(epochs):
        perm = torch.randperm(n, generator=gen)
        for i in range(0, n, bs):
            idx = perm[i:i + bs]
            opt.zero_grad()
            loss = torch.nn.functional.mse_loss(model(Xn_t[idx]), y_t[idx])
            loss.backward()
            opt.step()

    with torch.no_grad():
        Wn = model[0].weight.clone()
        bn = model[0].bias.clone()
        sd_t = torch.tensor(sd, dtype=torch.float32)
        mu_t = torch.tensor(mu, dtype=torch.float32)
        model[0].weight.copy_(Wn / sd_t)
        model[0].bias.copy_(bn - (Wn / sd_t) @ mu_t)
    model.eval()

    with torch.no_grad():
        mae = float((model(torch.tensor(X, dtype=torch.float32)) - y_t)
                    .abs().mean())
    torch.save(model.state_dict(), out_pt)
    print(f"final_train_mae={mae:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/train_model.py

cat > /app/evaluate.py <<'PY'
import sys

import pandas as pd
import torch

FEATURES = [f"x{i}" for i in range(6)]


def build_model():
    return torch.nn.Sequential(
        torch.nn.Linear(6, 24),
        torch.nn.Tanh(),
        torch.nn.Linear(24, 1),
    )


def main():
    if len(sys.argv) != 4:
        print("usage: evaluate.py <features_csv> <snapshot_pt> <out_txt>",
              file=sys.stderr)
        return 2
    feat_csv, snap_pt, out_txt = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        df = pd.read_csv(feat_csv)
    except Exception as e:
        print(f"error: unreadable CSV: {e}", file=sys.stderr)
        return 1
    missing = [c for c in FEATURES if c not in df.columns]
    if missing:
        print(f"error: missing columns: {missing}", file=sys.stderr)
        return 1
    if len(df) == 0:
        open(out_txt, "w").close()
        return 0
    try:
        X = df[FEATURES].astype(float).to_numpy()
    except Exception as e:
        print(f"error: malformed numeric value: {e}", file=sys.stderr)
        return 1

    try:
        state = torch.load(snap_pt, map_location="cpu", weights_only=True)
    except Exception as e:
        print(f"error: cannot load snapshot: {e}", file=sys.stderr)
        return 1
    model = build_model()
    model.load_state_dict(state)  # strict
    model.eval()

    with torch.no_grad():
        preds = model(torch.tensor(X, dtype=torch.float32)).squeeze(1).tolist()
    lines = [f"{p:.6f}" for p in preds]
    with open(out_txt, "w") as fh:
        fh.write("\n".join(lines) + ("\n" if lines else ""))
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/evaluate.py

python3 /app/train_model.py /app/data/train.csv /app/model.pt
python3 /app/evaluate.py /app/data/holdout.csv /app/model.pt /app/predictions.txt

echo "solve.sh done"
ls -l /app/train_model.py /app/evaluate.py /app/model.pt /app/predictions.txt
