# Fit and persist a support-ticket classifier

The helpdesk team needs a tiny, fully local text classifier. Your job is to
**fit** a multinomial Naive Bayes model on a labeled ticket corpus and
**persist the fitted model to a pickle file** so other jobs can reload it
later. Training happens in-process from the CSV; there is no network and no
third-party ML library involved.

## Files provided (do NOT modify them)

- `/app/data/tickets.csv` — the visible training corpus, with header
  `text,label`. Rows are `"<ticket text>",<label>` (texts may be quoted and
  contain commas; parse with the `csv` module). Labels are lowercase words.

Every corpus produced by the helpdesk export follows the same schema. Your
program must work for **any** conforming corpus, not just the provided file
(the verifier runs it on hidden corpora).

## The model you must fit (exact definitions)

Tokenization: the token set of a text is
`re.findall(r"[a-z0-9]+", text.lower())` — lowercase, then every maximal run
of ASCII letters/digits is one token. Punctuation-only texts yield **no**
tokens.

Given a corpus with `N` documents and class set `K` (the **sorted** list of
distinct label strings):

- `counts[c][t]` = number of occurrences of token `t` in documents of class
  `c`; `totals[c] = sum_t counts[c][t]`.
- `V` = the **sorted** list of all distinct tokens appearing anywhere in the
  corpus.
- `log_prior[c] = ln(N_c / N)` where `N_c` = number of documents labeled `c`.
- `log_likelihood[c][t] = ln((counts[c][t] + 1) / (totals[c] + len(V)))`
  (Laplace smoothing, alpha = 1). It is defined for **every** class `c` and
  **every** token `t` in `V` — including classes whose documents contain no
  tokens at all.

## Deliverables (both required)

1. `/app/fit.py` — a runnable Python program with this interface:

   ```
   python3 /app/fit.py <corpus_csv> <out_pkl>
   ```

   It fits the model defined above from `<corpus_csv>` and pickles it to
   `<out_pkl>` (plain `pickle.dump` of the dict below).

2. `/app/model_store/nb_model.pkl` — the fitted model for the visible corpus:

   ```
   python3 /app/fit.py /app/data/tickets.csv /app/model_store/nb_model.pkl
   ```

The pickled object must be a plain `dict` with EXACTLY these keys:

```python
{
  "model_type": "multinomial_nb",
  "alpha": 1.0,
  "classes": [...],          # sorted list of distinct label strings
  "vocab": [...],            # sorted list of all distinct tokens
  "log_prior": {class: float, ...},        # one entry per class
  "log_likelihood": {class: {token: float, ...}, ...},
}
```

- `log_likelihood[c]` must contain an entry for every token in `vocab`, for
  every class `c`.
- The file must be non-empty and reloadable with `pickle.load` in a fresh
  process.

## Edge cases the verifier probes

- A hidden corpus with a **different class set** and punctuation/number-heavy
  texts (tokens are extracted by the rule above, so `ref 88` yields
  `["ref", "88"]`).
- A hidden corpus containing documents whose text is **only punctuation** —
  they still count toward `N`, `N_c` and the class list, and their class still
  gets a full `log_likelihood` entry for every vocabulary token (via
  smoothing).
- The pickle must be loadable without any special classes on the path — only
  plain builtins (`dict`, `list`, `str`, `float`, `int`) inside.

## Constraints

- Pure Python 3 / standard library only (`csv`, `re`, `math`, `pickle`, ...).
  Do not install packages.
- Deterministic; no network access.
- Do not modify `/app/data/tickets.csv`.
