# slotd depot registry (amber-cistern fixture)

`slotd.py` is the depot slot registry service. Start it with:

    python3 /app/registry/slotd.py /app/registry/table.json 47331

It serves one JSON response per connection; see the top docstring of
`slotd.py` for the exact wire protocol. `table.json` maps slot keys
(`<ZONE>/<row>/<bay>`) to records; the visible manifest to probe lives at
`/app/registry/manifest.txt`.

Do not modify `slotd.py`, `table.json`, or `manifest.txt`.
