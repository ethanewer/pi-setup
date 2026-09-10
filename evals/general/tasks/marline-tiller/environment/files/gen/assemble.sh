#!/bin/bash
# Assemble the marline-lib repository at /app with a staged git history.
#
# Commits:
#   c1 scaffold: build tooling (vite lib mode + tsc declarations), utils, lockfile
#   c2 Counter   c3 QuantityInput   c4 TagPicker     (components + their tests)
#   c5 build-contract test          c6 API docs
#   c7 HEAD      refactor: "cavity state manager" — regresses the three
#                components AND the packaging (CJS-only, noEmit), which is the
#                state the agent is handed: suite red, build green but useless.
set -euo pipefail

REPO=/app
GEN="$(cd "$(dirname "$0")" && pwd)"
export GIT_AUTHOR_NAME="ana-marline" GIT_AUTHOR_EMAIL="ana@marline.local"
export GIT_COMMITTER_NAME="ana-marline" GIT_COMMITTER_EMAIL="ana@marline.local"

commit_at() {
  # commit_at <stamp> <message>
  local stamp="$1"; shift
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
    git commit --quiet -m "$1"
}

mkdir -p "$REPO"
cd "$REPO"
git init --quiet -b main

# ---- c1: scaffold ---------------------------------------------------------
cp -r "$GEN"/snap1/package.json "$GEN"/snap1/package-lock.json \
      "$GEN"/snap1/vite.config.ts "$GEN"/snap1/tsconfig.json \
      "$GEN"/snap1/tsconfig.build.json "$GEN"/snap1/vitest.config.ts \
      "$GEN"/snap1/vitest.setup.ts "$GEN"/snap1/.gitignore "$GEN"/snap1/LICENSE ./
mkdir -p src/components src/utils tests
cp -r "$GEN"/snap1/src/index.ts src/index.ts
cp -r "$GEN"/snap1/src/utils/. src/utils/
# Stage only the intended tree, never the generator itself: the repo history
# must contain the library's own files, not gen/ (the build-time generator
# lives at /app/gen and is removed after assembly).
git add package.json package-lock.json vite.config.ts tsconfig.json \
        tsconfig.build.json vitest.config.ts vitest.setup.ts .gitignore \
        LICENSE src
commit_at "2026-06-02T09:12:00+00:00" "chore: scaffold marline-lib (vite lib mode, vitest, tsconfigs, lockfile)"

# ---- c2..c4: components (correct implementations) + tests -----------------
for spec in \
  "2026-06-18T10:04:00+00:00|Counter.tsx|Counter.test.tsx|feat: Counter stepper with controlled/uncontrolled value modes" \
  "2026-06-25T11:22:00+00:00|QuantityInput.tsx|QuantityInput.test.tsx|feat: QuantityInput numeric entry with draft commits and arrow stepping" \
  "2026-07-03T14:41:00+00:00|TagPicker.tsx|TagPicker.test.tsx|feat: TagPicker chip multi-select with fresh-array callbacks"; do
  IFS='|' read -r stamp comp testfile msg <<<"$spec"
  cp "$GEN"/snap2/src/components/"$comp" src/components/"$comp"
  cp "$GEN"/snap2/tests/"$testfile" tests/"$testfile"
  git add src/components/"$comp" tests/"$testfile" && commit_at "$stamp" "$msg"
done

# ---- c5: build-contract test ---------------------------------------------
cp "$GEN"/snap2/tests/build.test.ts tests/build.test.ts
git add tests/build.test.ts && commit_at "2026-07-20T16:07:00+00:00" "test: build contract — ESM artifact and per-module type declarations"

# ---- c6: API documentation ------------------------------------------------
cp "$GEN"/snap2/README.md README.md
git add README.md && commit_at "2026-08-01T09:45:00+00:00" "docs: component API reference and markup contracts"

# ---- c7 (HEAD): the regressing refactor ------------------------------------
cp "$GEN"/snap3/src/components/Counter.tsx src/components/Counter.tsx
cp "$GEN"/snap3/src/components/QuantityInput.tsx src/components/QuantityInput.tsx
cp "$GEN"/snap3/src/components/TagPicker.tsx src/components/TagPicker.tsx
cp "$GEN"/snap3/vite.config.ts vite.config.ts
cp "$GEN"/snap3/tsconfig.build.json tsconfig.build.json
git add src/components/Counter.tsx src/components/QuantityInput.tsx \
        src/components/TagPicker.tsx vite.config.ts tsconfig.build.json
commit_at "2026-08-24T13:58:00+00:00" "refactor: cavity state manager, shared commit/nudge paths, splice-based chip toggling, CJS-only lib output + noEmit typecheck"

echo "assembled $(git rev-list --count HEAD) commits at $REPO"
