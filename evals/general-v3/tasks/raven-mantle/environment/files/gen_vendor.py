"""Build the raven-v1 local engine + shipped inputs (run once at docker build).

Produces under /app:
  engine/model/       - tiny causal GPT2-style decoder weights + config (local-only)
  engine/tokenizer/   - matching byte-level BPE tokenizer (local-only)
  engine/.baseline.sha256 - sha256 manifest of every source engine file
  config.json         - runtime config geometry used by infer.py and the verifier
  input/              - the shipped input fixtures that the default workflow consumes
"""
import hashlib, json, os, random
import numpy as np
import torch

torch.manual_seed(7331)
random.seed(7331)
np.random.seed(7331)

VE = "/app/engine"
MODEL = os.path.join(VE, "model")
TOK = os.path.join(VE, "tokenizer")

FEAT = 8          # instance/state feature dimension shared by bag & WDL heads
ENC = 16          # hidden width of the bag encoder / WDL encoder
MC = 4            # number of logits the bag-MIL classifier returns
WO = 3            # post-softmax outcome vector size (win/draw/loss)
MB = 3            # LM micro-batch size used for loss accumulation
DEFAULT_HEAD_COUNT = 5

# ------------------------------------------------------------------ tokenizer
from tokenizers import Tokenizer, models, pre_tokenizers, decoders, trainers

corpus = []
phrases = ["room", "kept", "thaw", "kings", "rooks", "left", "right", "pawn", "gambit",
           "castle", "endgame", "squared", "forfeit", "roam", "checkerboard", "midgame",
           "vault", "tempo", "outpost", "zwischenzug", "blunder", "zugzwang", "mated"]
random.shuffle(phrases)
for k in range(160):
    n = random.randint(2, 9)
    chosen = [phrases[(k + j) % len(phrases)] for j in range(n)]
    corpus.append(" ".join(chosen))
corpus_text = "\n".join(corpus)

tok = Tokenizer(models.BPE(unk_token="<unk>"))
tok.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=True)
tok.decoder = decoders.ByteLevel()
tr = trainers.BpeTrainer(vocab_size=160, special_tokens=["<unk>", "<pad>"])
tok.train_from_iterator(corpus, trainer=tr)
os.makedirs(TOK, exist_ok=True)
tok.save(os.path.join(TOK, "tokenizer.json"))

from transformers import PreTrainedTokenizerFast
fdtok = PreTrainedTokenizerFast(
    tokenizer_object=tok,
    bos_token="<unk>", eos_token="<unk>", unk_token="<unk>", pad_token="<pad>",
    model_max_length=256, padding_side="right",
)
fdtok.save_pretrained(TOK)
vocab_size = fdtok.vocab_size

# ------------------------------------------------------------------ model
from transformers import GPT2Config, GPT2LMHeadModel
gcfg = GPT2Config(
    vocab_size=vocab_size, n_positions=256, n_ctx=256, n_embd=32, n_layer=2,
    n_head=2, bos_token_id=fdtok.convert_tokens_to_ids("<unk>"),
    eos_token_id=fdtok.convert_tokens_to_ids("<unk>"),
    pad_token_id=fdtok.convert_tokens_to_ids("<pad>"),
)
model = GPT2LMHeadModel(gcfg)
model.save_pretrained(MODEL)

# ------------------------------------------------------------- baseline sha
def _walk(d):
    out = []
    for root, _, fs in os.walk(d):
        for f in sorted(fs):
            p = os.path.join(root, f)
            if p.endswith(".baseline.sha256") or os.path.islink(p):
                continue
            out.append(p)
    return out

import hashlib
man = {}
for p in _walk(VE):
    rel = os.path.relpath(p, VE)
    man[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
with open(os.path.join(VE, ".baseline.sha256"), "w") as fh:
    for k in sorted(man):
        fh.write(f"{man[k]}  {k}\n")

# ------------------------------------------------------------------ config
cfg = {
    "engine": "raven-v1",
    "model_dir": MODEL,
    "tokenizer_dir": TOK,
    "feat_dim": FEAT,
    "encoder_hidden": ENC,
    "milp_classes": MC,
    "wdl_outcomes": WO,
    "lm_mb": MB,
    "default_head_count": DEFAULT_HEAD_COUNT,
    "baseline_sha": os.path.join(VE, ".baseline.sha256"),
}
with open("/app/config.json", "w") as fh:
    json.dump(cfg, fh, indent=2)

# ------------------------------------------------------------------ inputs
os.makedirs("/app/input", exist_ok=True)
with open("/app/input/probe.txt", "w") as fh:
    fh.write("\n".join(corpus[10:10 + 5]) + "\n")  # 5 probe lines

# bag fixture
bag = np.random.default_rng(3).normal(size=(5, FEAT)).astype(np.float32)
np.savez("/app/input/bag.npz", X=bag)

# wdl state fixture: 9 legal-move candidates
state = np.random.default_rng(4).normal(size=(9, FEAT)).astype(np.float32)
np.savez("/app/input/state.npz", X=state)

# request stream fixture
rng = np.random.default_rng(5)
reqs = []
for i in range(14):
    reqs.append({"id": f"R{i+1}", "tokens": int(rng.choice([8, 16, 32]))})
stream = {
    "budget": {"mb": MB, "window": 900, "batch_tok": 300, "granularity": 4, "windows": 6},
    "requests": reqs,
}
with open("/app/input/requests.json", "w") as fh:
    json.dump(stream, fh, indent=2)

with open("/app/input/headcount.json", "w") as fh:
    json.dump({"count": DEFAULT_HEAD_COUNT}, fh)

print("vendor built; vocab_size=%d model=%s tok=%s" % (vocab_size, MODEL, TOK))
print("engine files:", len(man))