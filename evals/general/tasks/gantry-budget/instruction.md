# gantry-budget — keep the summarisation bus on budget

The image ships **gantry**, a batch summarisation deployment. It takes a
bus of funding-request records and produces one summary per record, with
the actual summarisation performed by a **billed** language model: the
deployment pays per token for every request it sends and for every
summary the model returns. Your job is to write the batch summariser that
runs this deployment — and to make sure the run fits the bill.

## Environment

| Path | What it is |
|---|---|
| `/app/docs/README.md` | the deployment notes: record format, model API, billing rules, config contract — read this first |
| `/app/gantry_client.py` | the billed model client (the only way to reach the model) |
| `/app/gantry_judge.py` | the quality judge the deployment uses to score summaries |
| `/app/tools/gen_records.py` | the fixture generator (used to build the data, kept for reference) |
| `/app/data/dev/records.jsonl` | the dev workload — 5000 records with `config.json` beside them |
| `/app/data/dev/config.json` | the dev deployment's budget and quality floor |

Python 3.12 with the standard library only. There is no network at trial
time and nothing to install: everything the job needs is on disk.

## Task

Write the batch summariser deliverable **`/app/summarizer.py`**. It is
invoked as:

```
python3 /app/summarizer.py --input DIR --output FILE
```

`DIR` contains a deployment: `records.jsonl` (the input bus) and
`config.json` (that deployment's settings). `FILE` is where the summaries
go. Read the deployment notes in `/app/docs/README.md` for the record
schema, the model API, the billing model and the configuration contract;
the gantry client and the judge are the ground truth on top.

The output contract: **one JSON object per line** at `FILE`, with exactly
the keys `id, title, amount, deadline, impact` (the model's response
fields), one line per input record, in the same order as the input bus,
every record exactly once.

## Acceptance protocol (what the grader re-runs)

The grader takes your `/app/summarizer.py` and runs it against **three
hidden deployments** the way it is run against the dev deployment, then
asserts, for each one:

1. every record appears in the output exactly once, in input order;
2. every record was actually processed by the model (its `id` shows up in
   the run's billing ledger);
3. the run's **total billed tokens** — recomputed authoritatively from the
   ledger and the output, using the billing rules in the README — do not
   exceed the deployment's `budget_tokens` in `config.json`;
4. at least `quality_floor` of the records' summaries are flawless
   according to `/app/gantry_judge.py`'s judgement contract.

All four must pass on every hidden deployment. The hidden deployments are
not this one: different records, a different budget, a different floor,
thicker or thinner records. Size your requests from the deployment you
are given, not from the dev numbers.

## Iterating locally

The dev deployment is right there: run your summarizer on it, inspect the
output and the ledger it produces, and score yourself with:

```
python3 /app/gantry_judge.py /app/data/dev/records.jsonl OUTPUT \
    "$(python3 -c "import json;print(json.load(open('/app/data/dev/config.json'))['quality_floor'])")"
```

The budget is the interesting part. How you spend it — what you send to
the model, how you break the 5000-record bus into requests, what you
truncate — is the assignment. A run that sends every section of every
record to the model bills millions of tokens on the dev set alone; the
deployment's budget for the whole dev run is far below that. Iterate
until all four checks hold on dev (the ledger shows exactly what was
billed), then the same job is what runs against the hidden deployments.

Do not modify `/app/gantry_client.py`, `/app/gantry_judge.py`,
`/app/docs/` or the data files; add your deliverable and nothing else.