# gantry summarisation service - deployment notes

`gantry` turns a bus of funding-request records into a one-line-per-record
summary bus. The summarisation itself is performed by a billed language
model; the deployment pays per token, so a job that is careless with what
it sends and how many requests it makes shows up directly on the bill.

## What is on disk

| Path | Meaning |
|---|---|
| `records.jsonl` | the input bus: one JSON object per line, one record per line |
| `config.json` | this deployment's settings (see below) |
| `gantry_client.py` | the billed model API (the only way to talk to the model) |
| `gantry_judge.py` | the quality judge used to score summaries |
| `summarizer.py` | the job runner you are expected to provide |

## Record schema

Each record is a JSON object:

```json
{
  "id": "rec00000",
  "title": "stacked corridor refresh",
  "sections": [
    {"head": "REQUEST", "text": "..."},
    {"head": "FUNDING", "text": "..."},
    {"head": "JUSTIFICATION", "text": "..."},
    {"head": "POLICY", "text": "..."},
    {"head": "HISTORY", "text": "..."},
    {"head": "BOILERPLATE", "text": "..."}
  ]
}
```

The narrative sections follow a fixed layout. Most of the prose is
context; the four facts a summary is judged on are:

1. **title** - the record's top-level `title` field;
2. **amount** - the dollar figure in the FUNDING section (the phrase
   "requests a budget of &lt;amount&gt; dollars");
3. **deadline** - the ISO date in the FUNDING section (the phrase
   "due no later than &lt;date&gt;");
4. **impact** - the sentence in the JUSTIFICATION section that starts with
   the word `Impact:` and runs to its end.

No other section contains an amount, an ISO date or an `Impact:` sentence,
so each of the three searches above is unambiguous.

## The model API (`gantry_client`)

The model is driven through blocks of text. Run:

```python
import gantry_client
client = gantry_client.GantryClient()
summary = client.summarize(block_text)          # one record, one request
summaries = client.summarize_many([blocks...])  # N records, one request
```

A block starts with a record header line `### RECORD <id>` and carries the
fields you want the model to see as labelled lines:

```
### RECORD rec00000
::TITLE:: stacked corridor refresh
::AMOUNT:: 48,643.35
::DEADLINE:: 2027-10-23
::IMPACT:: Impact: ... .
```

The model returns one summary object per block with exactly the keys
`id, title, amount, deadline, impact`; a block that omits a label yields
`None` for that key. Any other lines you include (excerpts, notes,
whole sections) are ignored by the model but still counted on the bill.
The record header is mandatory: a block without it is dropped and its
record is never billed (nor answered).

## Billing

The bill the model charges:

* **one token per whitespace-separated word** (`len(text.split())`);
* **150 tokens of fixed overhead per request** no matter how small;
* **output tokens** equal to the serialised size of the summaries the
  model returns.

Every request is appended to the ledger at the path named by the
environment variable `BILLING_LEDGER_PATH` (default:
`/tmp/gantry_ledger.jsonl`). The ledger is the only record the platform
trusts: a deployment decides what it is prepared to spend for a run and
rejects runs that cross the budget, whatever their output quality is.

## Config (`config.json`)

```json
{
  "records_file": "records.jsonl",
  "budget_tokens": 700000,
  "quality_floor": 0.95
}
```

* `budget_tokens` - the number of billed tokens the whole run may not
  exceed;
* `quality_floor` - the fraction of records whose summaries must be
  flawless (as measured by `gantry_judge.py`).

## The job you must provide

Write `/app/summarizer.py`. It is invoked as:

```
python3 /app/summarizer.py --input DIR --output FILE
```

where `DIR` holds `records.jsonl` and `config.json` and `FILE` is where
the summaries go. The summarizer reads the records, calls the billed
model, and writes **one JSON object per line** to `FILE` - in the exact
order of the input bus, every record exactly once - with keys
`id, title, amount, deadline, impact`.

A correct run must satisfy all of these, for the deployment whose config
it was given:

1. every record appears in the output exactly once, in input order;
2. every record is actually sent to the model (its `id` appears in the
   ledger);
3. the run's total billed tokens (recomputed from the ledger, using the
   billing rules above) do not exceed `budget_tokens`;
4. at least `quality_floor` of the summaries pass `gantry_judge.py`
   against the same records.

Checks 1-4 are what the grader re-runs, against deployments that are not
this one: same job, different records, different budget, different floor.
The job must therefore size its requests from the deployment it is given,
not from this dev layout.

## A note on the numbers

The dev deployment ships here (`data/dev/`): 5000 records, a
`data/dev/config.json` with its own budget and floor. A job that sends
every section of every record to the model bills several million tokens
on the dev set alone; and because the bill carries a fixed per-request
component on top of the content, the number of requests you make is a
real cost in itself. Both levers move the bill. Iterate on the dev
deployment until all four checks pass, then the hidden deployments at
grading time will run the same job.