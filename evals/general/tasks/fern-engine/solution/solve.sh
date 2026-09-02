#!/bin/bash
# Oracle for fern-engine: assembles the real deliverable /app/workflow.py (by
# writing the program) and then RUNS its train subcommand on the real /app
# data to produce the second deliverable /app/artifact. Never touches /tests.
set -eu

cat > /app/workflow.py <<'PY'
#!/usr/bin/env python3
"""fern-engine model-serve pipeline driver.

Subcommands:
  cache        SOURCE_DIR CACHE_DIR     -> copy model+tokenizer into a cache
  offline      CACHE_DIR PROMPT         -> load offline, greedy-generate
  train        DATA.csv OUT_DIR          -> train+serialize a classifier, reload
  predict      MODEL_DIR INPUT.csv       -> load saved classifier, label rows
  rebuild      STATE.pkl OUT_DIR         -> reconstruct arch from a state dict
  reconfigure  BASE_DIR OUT_DIR K        -> retarget head to K labels

Every command writes one JSON object to stdout on success, or a non-zero exit
status (with a message on stderr) on any invalid/malformed input.
"""
import csv
import json
import os
import sys
import torch
from torch import nn

from transformers import AutoModelForCausalLM, AutoTokenizer


def fail(msg):
    sys.stderr.write("workflow.py: error: %s\n" % msg)
    sys.exit(1)


class FernClassifier(nn.Module):
    def __init__(self, in_features, hidden_size, num_labels):
        super().__init__()
        self.encoder = nn.Linear(in_features, hidden_size)
        self.head = nn.Linear(hidden_size, num_labels)

    def forward(self, x):
        return self.head(torch.tanh(self.encoder(x)))


def save_classifier(dirpath, model):
    os.makedirs(dirpath, exist_ok=True)
    with open(os.path.join(dirpath, "config.json"), "w") as fh:
        json.dump(
            {
                "in_features": model.encoder.in_features,
                "hidden_size": model.encoder.out_features,
                "num_labels": model.head.out_features,
            },
            fh,
        )
    torch.save(model.state_dict(), os.path.join(dirpath, "state.pt"))


def load_classifier(dirpath):
    cfgp = os.path.join(dirpath, "config.json")
    if not os.path.isfile(cfgp):
        fail("model dir has no config.json: %s" % dirpath)
    with open(cfgp) as fh:
        cfg = json.load(fh)
    model = FernClassifier(cfg["in_features"], cfg["hidden_size"], cfg["num_labels"])
    st = torch.load(os.path.join(dirpath, "state.pt"), map_location="cpu")
    model.load_state_dict(st)
    model.eval()
    return model


def read_rows(path):
    if not os.path.isfile(path):
        fail("missing file: %s" % path)
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    if len(rows) < 2:
        fail("file has no data rows: %s" % path)
    header = [c.strip() for c in rows[0]]
    if len(header) < 2:
        fail("too few columns in %s" % path)
    return header, rows[1:]


# ---------------------------------------------------------------- train
def cmd_train(data_csv, out_dir):
    header, rows = read_rows(data_csv)
    feats = header[:-1]
    X, y = [], []
    for row in rows:
        row = [c.strip() for c in row]
        if len(row) != len(header):
            fail("ragged row in %s: %r" % (data_csv, row))
        try:
            x = [float(v) for v in row[:-1]]
            lab = int(float(row[-1]))
        except ValueError:
            fail("non-numeric value in %s" % data_csv)
        X.append(x)
        y.append(lab)
    uniq = sorted(set(y))
    if len(uniq) < 2:
        fail("need at least two distinct labels in %s" % data_csv)
    num_labels = max(uniq) + 1
    hidden = 8

    torch.manual_seed(0)
    model = FernClassifier(len(feats), hidden, num_labels)
    Xt = torch.tensor(X, dtype=torch.float32)
    yt = torch.tensor(y, dtype=torch.long)
    opt = torch.optim.Adam(model.parameters(), lr=0.05)
    crit = nn.CrossEntropyLoss()
    model.train()
    for _ in range(120):
        opt.zero_grad()
        loss = crit(model(Xt), yt)
        loss.backward()
        opt.step()
    model.eval()

    save_classifier(out_dir, model)
    # reload the artifact and confirm it reproduces the exact predictions.
    reloaded = load_classifier(out_dir)
    with torch.no_grad():
        a = model(Xt).argmax(dim=1)
        b = reloaded(Xt).argmax(dim=1)
        reload_ok = bool((a == b).all().item())
    print(json.dumps({"artifact": out_dir, "num_labels": num_labels,
                      "hidden_size": hidden, "reload_ok": reload_ok,
                      "rows_seen": len(X)}))


# ------------------------------------------------------------------ predict
def cmd_predict(model_dir, input_csv):
    model = load_classifier(model_dir)
    header, rows = read_rows(input_csv)
    X = []
    for row in rows:
        row = [c.strip() for c in row]
        if len(row) != len(header):
            fail("ragged input row in %s" % input_csv)
        try:
            X.append([float(v) for v in row])
        except ValueError:
            fail("non-numeric value in %s" % input_csv)
    if len(X) == 0:
        fail("no data rows in %s" % input_csv)
    with torch.no_grad():
        Xt = torch.tensor(X, dtype=torch.float32)
        Logits = model(Xt)
        preds = Logits.argmax(dim=1).tolist()
    print(json.dumps({"predictions": [int(p) for p in preds],
                      "num_labels": model.head.out_features}))


# ------------------------------------------------------------ cache/offline
def cmd_cache(source_dir, cache_dir):
    if not os.path.isfile(os.path.join(source_dir, "config.json")):
        fail("source dir missing a transformer config: %s" % source_dir)
    model = AutoModelForCausalLM.from_pretrained(source_dir)
    try:
        tok = AutoTokenizer.from_pretrained(source_dir)
    except Exception as exc:
        fail("source dir has no usable tokenizer: %r" % exc)
    model.save_pretrained(cache_dir)
    tok.save_pretrained(cache_dir)
    print(json.dumps({"cached": cache_dir,
                      "files": sorted(os.listdir(cache_dir))}))


def cmd_offline(cache_dir, prompt):
    if not prompt or not str(prompt).strip():
        fail("empty probe prompt")
    if not os.path.isdir(cache_dir):
        fail("cache dir does not exist: %s" % cache_dir)
    model = AutoModelForCausalLM.from_pretrained(cache_dir, local_files_only=True)
    tok = AutoTokenizer.from_pretrained(cache_dir, local_files_only=True)
    model.eval()
    model.config.eos_token_id = None
    model.config.pad_token_id = 0
    model.generation_config.eos_token_id = None
    model.generation_config.pad_token_id = 0
    ids = tok(prompt, return_tensors="pt", truncation=True, max_length=48)
    with torch.no_grad():
        out = model.generate(**ids, max_new_tokens=4, do_sample=False,
                             early_stopping=False)
    new_tokens = int(out.shape[1] - ids["input_ids"].shape[1])
    generated = tok.decode(out[0], skip_special_tokens=True)
    print(json.dumps({"new_tokens": new_tokens,
                      "generated": generated,
                      "prompt": prompt}))


# ------------------------------------------------------------------ rebuild
def cmd_rebuild(state_pkl, out_dir):
    try:
        sd = torch.load(state_pkl, map_location="cpu")
    except Exception as exc:
        fail("state dict file cannot be loaded: %r" % exc)
    if not isinstance(sd, dict):
        fail("state file is not a torch state dict")
    want = {"encoder.weight", "encoder.bias", "head.weight", "head.bias"}
    if set(sd.keys()) != want:
        fail("state keys do not match a FernClassifier: %s" % sorted(sd.keys()))
    ew = sd["encoder.weight"]
    hw = sd["head.weight"]
    hidden = ew.shape[0]
    in_f = ew.shape[1]
    k = hw.shape[0]
    if (ew.shape != (hidden, in_f) or sd["encoder.bias"].shape != (hidden,)
            or hw.shape != (k, hidden) or sd["head.bias"].shape != (k,)):
        fail("state shapes are internally inconsistent")
    model = FernClassifier(in_f, hidden, k)
    model.load_state_dict(sd)  # strict; extra/missing keys must fail
    save_classifier(out_dir, model)
    print(json.dumps({"in_features": in_f, "hidden_size": hidden,
                      "num_labels": k, "loaded": True}))


# --------------------------------------------------------------- reconfigure
def cmd_reconfigure(base_dir, out_dir, k_arg):
    cfgp = os.path.join(base_dir, "config.json")
    if not os.path.isfile(cfgp):
        fail("base model dir has no config.json: %s" % base_dir)
    with open(cfgp) as fh:
        base = json.load(fh)
    try:
        k = int(k_arg)
    except (TypeError, ValueError):
        fail("K must be an integer")
    if k < 1:
        fail("K must be >= 1")
    model = FernClassifier(base["in_features"], base["hidden_size"], k)
    save_classifier(out_dir, model)
    print(json.dumps({"base": base_dir, "num_labels": k, "out_dir": out_dir,
                      "out_features": model.head.out_features}))


CMDS = {
    "train": cmd_train,
    "predict": cmd_predict,
    "cache": cmd_cache,
    "offline": cmd_offline,
    "rebuild": cmd_rebuild,
    "reconfigure": cmd_reconfigure,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in CMDS:
        sys.stderr.write(
            "usage: workflow.py <train|predict|cache|offline|rebuild|reconfigure> ...\n")
        return 2
    cmd = argv[1]
    n = {"train": 4, "predict": 4, "cache": 4, "offline": 4,
         "rebuild": 4, "reconfigure": 5}[cmd]
    if len(argv) != n:
        sys.stderr.write("wrong number of arguments for '%s'\n" % cmd)
        return 2
    CMDS[cmd](* argv[2:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x /app/workflow.py

# Run the pipeline on the real visible data to produce the required artifact.
python3 /app/workflow.py train /app/data/train.csv /app/artifact >/dev/null
echo "solve.sh: wrote /app/workflow.py and trained /app/artifact" >&2