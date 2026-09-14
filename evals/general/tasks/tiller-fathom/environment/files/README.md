# tiller-fathom — working environment

This image contains two checkouts of the Prettier formatter:

- `/app/src`      — the checkout you work in (buggy commit, branch `work`,
                    dependencies installed). Fix the formatter here.
- `/app/pristine` — a frozen identical pre-fix checkout. Do not modify it.

## Useful commands

    # format one TypeScript file (prints to stdout)
    node /app/src/bin/prettier.js file.ts

    # the project's quote-props regression suite
    cd /app/src && node_modules/.bin/jest --ci --runInBand tests/format/typescript/quote-props

    # the broader TypeScript formatting span
    cd /app/src && node_modules/.bin/jest --ci --runInBand tests/format/typescript

There is no network access in this container; everything is preinstalled.