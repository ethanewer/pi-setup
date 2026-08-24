# Placeholder substitution

`/app/template.txt` is a text template that contains **placeholders** in
`{{token}}` form:

- `{{name}}`, `{{event}}`, `{{date}}`, `{{venue}}`

`/app/vars.json` is a JSON object mapping each token name to its replacement
value, e.g. `{"name": "Ada", ...}`.

Replace **every** `{{token}}` occurrence in the template with the corresponding
value from `vars.json` (there is exactly one key per distinct placeholder, and
every placeholder in the template has a key). Do not leave any `{{...}}` markers
in the output.

Write the fully substituted text to `/app/output.txt`.

When done, confirm `/app/output.txt` exists and contains the substituted template
with no remaining placeholders.