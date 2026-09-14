#!/usr/bin/env bash
# tiller-fathom oracle: reproduce the defect on the untouched pre-fix tree,
# apply the fix to the formatter source, and record the fixed output.
# Mirrors what a correct agent delivers.
set -euo pipefail

mkdir -p /app/repro

# 1. The reproduction: an interface plus a type literal, each with a quoted
#    method named "new" alongside an ordinary (safe-identifier) method.
cat > /app/repro/repro.ts <<'EOF'
interface Container {
  "new"(id: string): number;
  "method"(): void;
}

type ContainerType = {
  'new'(id: string): number;
  'method'(): void;
};
EOF

# 2. Pre-fix observation: run the pristine (unmodified, buggy) tree. Output
#    must drop the quotes, turning the members into construct signatures.
node /app/pristine/bin/prettier.js /app/repro/repro.ts > /app/repro/before.txt
grep -qE '(^|[[:space:]])new\(' /app/repro/before.txt

# 3. The fix: the same guard the upstream fix adds to the quote-props
#    unquoting decision in the formatter source.
git -C /app/src apply /solution/fix.patch

# 4. Post-fix observation: quotes must be preserved on the "new" methods.
node /app/src/bin/prettier.js /app/repro/repro.ts > /app/repro/out.txt
grep -q '"new"(' /app/repro/out.txt

echo "oracle: reproduction captured, fix applied, fixed output recorded"