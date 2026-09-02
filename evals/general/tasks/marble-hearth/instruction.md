# marble-hearth — Offline inference appliance on a pinned toolchain

You are commissioning the **marble-hearth** inference appliance: a small,
air-gapped next-token scorer that must run **fully offline** on top of the
platform's preinstalled, **pinned** ML toolchain, plus a dependency
installation script that extends the environment *without disturbing* that
toolchain.

## Environment

Working directory: `/app`. Python 3.12 is available as `python3`. The image
already contains:

- `/app/model_store/hearth-mini/` — a tiny local causal-LM model store
  (GPT2-style, word-level tokenizer) saved in `transformers` format. Load it
  **only from disk**; never fetch anything from the hub.
- `/app/prompts.txt` — the visible prompt batch (one prompt per line; blank
  lines are separators and must be skipped).
- `/app/pkgs/hearthrt_pkg/` — the local source tree of the `hearthrt` helper
  package (its only public constant is `hearthrt.APPLIANCE_ID`).

**The pinned toolchain is immutable.** `torch` version `2.13.0`
(`torch.__version__` reports the `+cu130` build qualifier) and `transformers`
version `5.16.1` are preinstalled and must survive **bit-for-bit**: you may not
upgrade, downgrade, uninstall, or reinstall either of them. The offline load
path of the appliance is wired to these exact versions.

## Deliverables (all three required)

1. `/app/install_extras.sh` — an executable, **idempotent** bash installer that
   adds the appliance's extra dependencies to the **system** Python:

   - `attrs==25.3.0` and `six==1.17.0` from the package index;
   - the local package `hearthrt` installed from `/app/pkgs/hearthrt_pkg`
     (an offline install — it needs no network beyond build tooling already
     present).

   After it runs, `import attrs`, `import six`, and `import hearthrt` must all
   succeed in `python3` at exactly those versions. Re-running the script must
   be safe and must exit 0. It must **never** touch `torch` or `transformers`
   (no upgrade, downgrade, reinstall, or dependency cascade that would replace
   them).

2. `/app/infer.py` — a runnable Python program with this interface:

   ```
   python3 /app/infer.py <model_dir> <prompts.txt> <out_json>
   ```

   It must load the tokenizer and causal LM **from `<model_dir>` on disk**
   (`local_files_only=True`; no network), then for every non-blank line of the
   prompts file compute the model's predicted next token:

   - tokenize the prompt with `add_special_tokens=False`;
   - run the model in eval mode under `torch.no_grad()`;
   - take the **argmax of the logits at the last position** → the predicted
     token id;
   - record `next_token` as `tokenizer.decode([next_token_id])`.

   Output JSON schema (exactly these keys, prompts in input order):

   ```json
   {
     "appliance_id": "<value of hearthrt.APPLIANCE_ID>",
     "results": [
       {"prompt": "<line>", "next_token_id": <int>, "next_token": "<str>"}
     ]
   }
   ```

   `appliance_id` must come from the installed `hearthrt` package (import it;
   do not hard-code the string). The program must work on **any** model store
   and prompts file that follow this format, not just the visible ones.

3. `/app/batch_output.json` — the output your program produces on the visible
   batch:

   ```
   python3 /app/infer.py /app/model_store/hearth-mini /app/prompts.txt /app/batch_output.json
   ```

## Edge cases the grader probes with hidden inputs

- Different model stores (different vocabularies/weights) and different prompt
  batches — nothing may be hard-coded to the visible fixtures.
- Blank lines anywhere in the prompts file → skipped, no result entry.
- The results order must match the prompt order exactly.
- The toolchain integrity is re-checked after your installer has run: the
  pinned `torch`/`transformers` versions and the offline load of a model store
  through them must be exactly as delivered by the platform.

## Constraints

- Do not modify `/app/model_store/`, `/app/pkgs/`, or `/app/prompts.txt`.
- The grader runs `/app/infer.py` **unchanged** on hidden inputs with
  `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` set, so the offline load path
  must genuinely work.
- Standard data-science stack only; the pinned toolchain plus the extras you
  install. Do not replace the pinned toolchain with anything else.
