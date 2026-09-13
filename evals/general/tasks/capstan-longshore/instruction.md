# EXECUTE reports the missing named parameters in an unpredictable order

## Situation

`/app/src` is a shallow, pinned clone of the DuckDB source repository
(`https://github.com/duckdb/duckdb`) at upstream commit
`9c21294d984dfe9a1da5d055b5fce3e8a0d634b2`, checked out in detached HEAD.
The release engine has already been configured and compiled, so everything
works entirely offline. There is **no network** at trial time: `git fetch`,
`curl` and any other network use will fail.

The prebuilt CLI binary is `/app/src/build/release/duckdb` and the project's
own test runner is `/app/src/build/release/test/unittest`. Because the build
is already done, a source edit only triggers an incremental recompile plus a
relink:

```
cd /app/src && ninja -C build/release
```

Each cycle is on the order of fifteen to twenty minutes on this machine's
single CPU, not hours. Do **not** reconfigure or clean the build directory.

## The bug

DuckDB's `EXECUTE` runs a prepared statement and lets you pass values for
each of its named parameters, e.g. `EXECUTE q(aa := 1, bb := 2)`. If a value
for a parameter is missing, the engine refuses with an error that lists which
parameters were not provided:

```
Invalid Input Error: Values were not provided for the following parameters: ee, cc, dd
```

The problem is the **order of that list**. The statement above declares its
parameters in the order `$aa, $bb, $cc, $dd, $ee` — the error is about `$cc`,
`$dd` and `$ee` — yet the list prints as `ee, cc, dd`. The order is not
stable or meaningful: it reflects how the engine happens to collect the
missing names internally, so it changes with the names, how many are
missing, and even the build. Users and tools that parse this message expect
the missing parameters in the order they appear in the statement.

Reproduce it yourself with the prebuilt CLI:

```
/app/src/build/release/duckdb -c 'PREPARE q03 AS SELECT $aa, $bb, $cc, $dd, $ee; EXECUTE q03(aa := 1, bb := 2);'
```

On this image it prints the error with the missing parameters in an order
unrelated to the declaration. After a correct fix the exact same command
must print:

```
Invalid Input Error: Values were not provided for the following parameters: cc, dd, ee
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. The project's own regression test for this bug,
   `test/sql/prepared/prepared_named_param.test`, passes. Run it with the
   project's test runner:

   ```
   cd /app/src && build/release/test/unittest "test/sql/prepared/prepared_named_param.test"
   ```

   At the pinned commit this fails (one statement block expects the missing
   parameters in declaration order, and the engine reports them out of
   order); after your fix it must print `All tests passed`. The test also
   covers the other prepared-statement behaviours (parameter reuse, value
   binding, positional parameters), so it enforces that your fix does not
   over-reach.

2. Whenever `EXECUTE` is missing values for named parameters, the error
   message reports the missing parameters **in the order they are declared in
   the statement**, whatever the names are, however many are missing, and no
   matter which subset was supplied. A two-parameter statement must never
   print them swapped; supplying a name that is declared more than once must
   satisfy every occurrence so that name never appears in the error.

3. Everything that worked before still works: supplying all parameters never
   produces the error, and statements that were rejected for other reasons
   (mixing named and positional parameters, non-scalar arguments, parameter
   count mismatches) are still rejected with the same messages.

Run the project's own prepared-statement suite to confirm you broke nothing
else:

```
cd /app/src && build/release/test/unittest "test/sql/prepared/*"
```

The tests in the tree are the spec: take them as authoritative.

Write a short root-cause note to `/app/explanation.md`: what the message is
supposed to promise, where the unstable order came from, and the minimal
change you made to stabilise it. A few sentences are enough.

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is a deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, stage,
  or change build files, and do not add or rename files inside the
  repository — the tree must remain the same clone of the same revision,
  with only the code fix applied to the working tree.
- The regression-test file `test/sql/prepared/prepared_named_param.test` is
  part of the image the way the project intends it; the verifier checks that
  it stays byte-identical to the upstream regression test.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change and the regression-test file the image already
   carries, and nothing new inside the repository.
2. The regression test `test/sql/prepared/prepared_named_param.test` passes
   through the project's own `unittest` runner, and the project's own
   `test/sql/prepared/*` suite stays green.
3. The exact reproduction above prints `cc, dd, ee`.
4. Hidden cases: further `EXECUTE` calls that hit the same code path from
   inputs the upstream regression test does not use (other parameter names,
   other numbers of missing parameters, a repeated declaration name, an
   empty supply, an all-supplied call) must produce the missing-parameter
   error with the names in declaration order, and the all-supplied call must
   return the values in declaration order.

Deliverables: the repaired `/app/src` tree and the note at
`/app/explanation.md`.