# rose-orchard harvest hub
Two releases are published on the hub: config `bulk` (aggregate yield per plot)
and config `paired` (trial/control pairs). The GOLD release that the product
team wants for reporting is the `bulk` config; within it the *reserved* split is
`holdout` (the rows set aside for final reporting). The integer metric to report
per row is the `yield` column. Load ONLY the bulk/holdout slice.
