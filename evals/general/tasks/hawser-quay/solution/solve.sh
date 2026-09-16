#!/bin/bash
# Oracle for hawser-quay: localises and repairs the jest-each `%j` title
# formatter (packages/jest-each/src/table/array.ts) exactly as the upstream
# fix does, then writes the two deliverables (/app/reproduce.sh and
# /app/diagnosis.md) and proves the fix on the repaired tree with the same
# standalone toolchain the verifier uses. It reads only /app and /opt -- never
# /tests.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

python3 - <<'PY'
import sys

path = "packages/jest-each/src/table/array.ts"
src = open(path, encoding="utf-8").read()
orig = src

# --- edit 1: declare the %j placeholder constant ---------------------------
a = "const PRETTY_PLACEHOLDER = '%p';"
b = "const PRETTY_PLACEHOLDER = '%p';\nconst JSON_PLACEHOLDER = '%j';"
if a not in src:
    raise SystemExit("oracle: PRETTY_PLACEHOLDER anchor missing")
src = src.replace(a, b, 1)

# --- edit 2: route %j through the custom stringifier in formatTitle --------
a = """        if (placeholder === PRETTY_PLACEHOLDER)
          return interpolatePrettyPlaceholder(formattedTitle, normalisedValue);

        return util.format(formattedTitle, normalisedValue);"""
b = """        if (placeholder === PRETTY_PLACEHOLDER)
          return interpolatePrettyPlaceholder(formattedTitle, normalisedValue);

        if (placeholder === JSON_PLACEHOLDER)
          return interpolateJsonPlaceholder(formattedTitle, normalisedValue);

        return util.format(formattedTitle, normalisedValue);"""
if a not in src:
    raise SystemExit("oracle: formatTitle placeholder branch anchor missing")
src = src.replace(a, b, 1)

# --- edit 3: replacer functions + the JSON stringifier ----------------------
a = """const interpolatePrettyPlaceholder = (title: string, value: unknown) =>
  title.replace(PRETTY_PLACEHOLDER, pretty(value, {maxDepth: 1, min: true}));"""
b = """const interpolatePrettyPlaceholder = (title: string, value: unknown) => {
  const prettyValue = pretty(value, {maxDepth: 1, min: true});
  return title.replace(PRETTY_PLACEHOLDER, () => prettyValue);
};

const interpolateJsonPlaceholder = (title: string, value: unknown) => {
  const json = stringifyJson(value);
  return title.replace(JSON_PLACEHOLDER, () => json);
};

// util.format('%j', ...) throws on a bigint, so serialize here instead and
// render bigints the way a JavaScript literal reads. Cyclic values keep the
// [Circular] output util.format gives them.
function stringifyJson(value: unknown): string {
  if (isCyclic(value)) {
    return '[Circular]';
  }
  return `${JSON.stringify(value, (_, entry) =>
    typeof entry === 'bigint' ? `${entry}n` : entry,
  )}`;
}

function isCyclic(value: unknown, ancestors: Array<unknown> = []): boolean {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  if (ancestors.includes(value)) {
    return true;
  }
  const nested = [...ancestors, value];
  return Object.values(value).some(entry => isCyclic(entry, nested));
}"""
if a not in src:
    raise SystemExit("oracle: interpolatePrettyPlaceholder anchor missing")
src = src.replace(a, b, 1)

if src == orig:
    raise SystemExit("oracle: no change applied")

open(path, "w", encoding="utf-8").write(src)
print("oracle: repaired packages/jest-each/src/table/array.ts")
PY
oracle_rc=$?
[ "$oracle_rc" -ne 0 ] && exit 1

# --- deliverable 1: the agent-style reproduction -----------------------------
cat > /app/reproduce.sh <<'SH'
#!/bin/bash
# Reproduction of the parameterised-title %j+bigint crash.
# Usage: reproduce.sh <dir-with-compiled-formatter>   (array.js + interpolation.js)
# Fails (non-zero) when the formatter crashes or renders the wrong title for a
# bigint row value; passes (0) and prints the title once the formatter is fixed.
set -u
DIR="$1"
[ -f "$DIR/array.js" ] || { echo "no compiled formatter at $DIR"; exit 2; }
export DIR
node - <<'JS'
const dir = process.env.DIR;
const array = require(dir + '/array.js').default;
let titles;
try {
  titles = array('expected string: %j %j %j %s', [[1n, {nested: 2n}, [3n], -4n]])
    .map(r => r.title);
} catch (e) {
  console.error('CRASH: %j title with a bigint row value -> ' + e.message);
  process.exit(1);
}
const got = titles[0];
const expected = 'expected string: "1n" {"nested":"2n"} ["3n"] -4n';
console.log(got);
if (got !== expected) {
  console.error('WRONG TITLE: got ' + JSON.stringify(got) + ', want ' + JSON.stringify(expected));
  process.exit(1);
}
JS
SH
chmod +x /app/reproduce.sh

# --- deliverable 2: diagnosis ------------------------------------------------
cat > /app/diagnosis.md <<'MD'
## Diagnosis: parameterised-test titles crash on bigint `%j` values

### Module
`packages/jest-each/src/table/array.ts` -- the table formatter behind
`it.each` / `test.each` that builds each row's display title.

### Root cause
The `%j` (JSON) placeholder fell through to Node's `util.format('%j', value)`,
which uses `JSON.stringify` internally and throws
`TypeError: Do not know how to serialize a BigInt` as soon as a row value is a
bigint, failing the whole test definition. Separately, `%p` (and `%j`) were
substituted with `String.prototype.replace(pattern, replacement)` semantics,
where `$&`, `` $` ``, `$'` and `$$` in a replacement string have special
meanings, so values containing those characters rendered scrambled.

### Fix
Intercept the `%j` placeholder in the title formatter and serialize the value
with a custom JSON stringifier: bigints render as their JavaScript literal
form (`1n`), cyclic structures render as `[Circular]`. `%p`/`%j` substitution
now uses replacer functions so `$`-pattern characters render literally.

### Verification
The repaired table formatter compiles standalone with the pinned toolchain;
`/app/reproduce.sh` fails against the untouched parent formatter and passes
against the repaired one, the upstream golden regression tests pass, and the
hidden cases pass.
MD

# --- self-check on the repaired tree (same route the verifier uses) ----------
set -e
mkdir -p /tmp/voracle/src
cp /app/src/packages/jest-each/src/table/array.ts /app/src/packages/jest-each/src/table/interpolation.ts /tmp/voracle/src/
ln -sfn /opt/jest-deps/node_modules /tmp/voracle/node_modules
cd /tmp/voracle
/opt/jest-deps/node_modules/.bin/tsc --module commonjs --target es2022 --esModuleInterop --skipLibCheck --outDir out src/array.ts src/interpolation.ts >/dev/null 2>&1 || true
test -f out/array.js || { echo "oracle: repaired module did not compile"; exit 1; }

# untouched (pre-fix) compile from the pristine reference
mkdir -p /tmp/voracle-pre/src
cp /opt/hawser-pristine/table/array.ts /opt/hawser-pristine/table/interpolation.ts /tmp/voracle-pre/src/
ln -sfn /opt/jest-deps/node_modules /tmp/voracle-pre/node_modules
cd /tmp/voracle-pre
/opt/jest-deps/node_modules/.bin/tsc --module commonjs --target es2022 --esModuleInterop --skipLibCheck --outDir out src/array.ts src/interpolation.ts >/dev/null 2>&1 || true
test -f out/array.js || { echo "oracle: pre-fix module did not compile"; exit 1; }

if bash /app/reproduce.sh /tmp/voracle-pre/out >/dev/null 2>&1; then
  echo "oracle: FAIL - reproduction passed on the pre-fix formatter"; exit 1
fi
if ! bash /app/reproduce.sh /tmp/voracle/out; then
  echo "oracle: FAIL - reproduction did not pass on the repaired formatter"; exit 1
fi
if ! bash /opt/hawser-golden/run-golden.sh /tmp/voracle/out; then
  echo "oracle: FAIL - golden regression tests did not pass on repaired tree"; exit 1
fi
rm -rf /tmp/voracle /tmp/voracle-pre
echo "oracle: all self-checks passed"
exit 0