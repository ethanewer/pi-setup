#!/usr/bin/env python3
"""Ember Atlas — fetch a pretrained model + tokenizer into the local HF cache
for offline reuse.

python3 fetch_model.py fetch  --endpoint URL --repo-id ID --cache DIR
python3 fetch_model.py verify --repo-id ID --cache DIR --prompt TEXT
"""
import argparse
import json
import os
import sys


def die(msg, code=2):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(code)


def cmd_fetch(args):
    from huggingface_hub import snapshot_download

    try:
        path = snapshot_download(
            args.repo_id, endpoint=args.endpoint.rstrip("/"),
            cache_dir=args.cache)
    except Exception as e:
        die("fetch failed for %s: %s" % (args.repo_id, e))

    files = sorted(os.listdir(path))
    if "config.json" not in files:
        die("cached snapshot has no model config.json")
    if not any(f.endswith((".safetensors", ".bin")) for f in files):
        die("cached snapshot has no model weight file")
    if not any(f.startswith("tokenizer") for f in files):
        die("cached snapshot has no tokenizer assets")

    refs = os.path.join(args.cache,
                        "models--%s" % args.repo_id.replace("/", "--"),
                        "refs", "main")
    revision = None
    try:
        with open(refs) as fh:
            revision = fh.read().strip()
    except Exception:
        pass
    print(json.dumps({
        "cached": args.repo_id,
        "cache_dir": args.cache,
        "files": files,
        "revision": revision,
    }))


def cmd_verify(args):
    if not args.prompt:
        die("prompt must be a non-empty string")
    if not os.path.isdir(args.cache):
        die("cache dir does not exist: %s" % args.cache)

    import torch  # noqa: F401
    from transformers import AutoModelForCausalLM, AutoTokenizer
    try:
        tok = AutoTokenizer.from_pretrained(
            args.repo_id, cache_dir=args.cache, local_files_only=True)
        model = AutoModelForCausalLM.from_pretrained(
            args.repo_id, cache_dir=args.cache, local_files_only=True)
    except Exception as e:
        die("offline load failed for %s: %s" % (args.repo_id, e))
    model.eval()
    with torch.no_grad():
        ids = tok(args.prompt, return_tensors="pt")
        out = model.generate(
            **ids, max_new_tokens=4, do_sample=False, num_beams=1,
            pad_token_id=tok.pad_token_id if tok.pad_token_id is not None
            else tok.eos_token_id)
    new_tokens = out[0][ids["input_ids"].shape[1]:]
    print(json.dumps({
        "repo_id": args.repo_id,
        "prompt": args.prompt,
        "new_tokens": 4,
        "generated": tok.decode(new_tokens, skip_special_tokens=True),
    }))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch")
    f.add_argument("--endpoint", required=True)
    f.add_argument("--repo-id", required=True)
    f.add_argument("--cache", required=True)
    f.set_defaults(fn=cmd_fetch)

    v = sub.add_parser("verify")
    v.add_argument("--repo-id", required=True)
    v.add_argument("--cache", required=True)
    v.add_argument("--prompt", required=True)
    v.set_defaults(fn=cmd_verify)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
