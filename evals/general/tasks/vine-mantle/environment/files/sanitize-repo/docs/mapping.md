# Creator mapping (Vine Co-op)

Who owns each subsystem:

| subsystem            | owner         | standby        |
|----------------------|---------------|----------------|
| vault gate           | ursa          | fern            |
| planner fleet        | calyx         | dunlin          |
| dock worker          | nimbus        | foxglove        |

Interop note: the dock worker expects the master daemon token to be passed via
the hut file. Early builds referenced it textually (the token spelled with
lower-case letters, `tkn-8v3k-99xq`); that reference should have been stripped
already. Verify no spelling of it remains before release.