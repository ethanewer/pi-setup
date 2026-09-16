#!/bin/bash
# Oracle for dunnage-light: repairs the clap checkout at /app/src.
#
# The real upstream fix (commit 3eacf5b8) forwards the plain argument id
# instead of its pre-hashed key in the list-of-conditions OS-string flavour,
# so each stored conditional id matches the parsed argument's id. The oracle
# applies that one-line change, authors the reproduction test deliverable
# (deliverable: /app/src/tests/builder/dunnage_repro.rs), registers it with
# the project's harness, and proves the repaired tree: the reproduction
# passes and the whole builder suite stays green.
set -e
cd /app/src

echo "== applying the fix =="
python3 - <<'PY'
from pathlib import Path
p = Path('src/builder/arg.rs')
s = p.read_text()
old = 'self = self.default_value_if_os(arg.key(), *val, *default);'
new = 'self = self.default_value_if_os(arg, *val, *default);'
assert old in s, 'buggy line not found in src/builder/arg.rs'
p.write_text(s.replace(old, new, 1))
print('patched', p)
PY

echo "== writing the reproduction test deliverable =="
cat > tests/builder/dunnage_repro.rs <<'EOF'
use clap::{Arg, ArgSettings, Command};
use std::ffi::OsStr;

#[test]
fn default_value_ifs_os_repro() {
    let cmd = Command::new("my_cargo")
        .arg(
            Arg::new("flag")
                .long("flag")
                .allow_invalid_utf8(true)
                .takes_value(true),
        )
        .arg(
            Arg::new("other")
                .long("other")
                .allow_invalid_utf8(true)
                .default_value_ifs_os(&[(
                    "flag",
                    Some("标记2").map(OsStr::new),
                    Some("flag=标记2").map(OsStr::new),
                )]),
        );
    let result = cmd.try_get_matches_from([
        OsStr::new("my_cargo"),
        OsStr::new("--flag"),
        OsStr::new("标记2"),
    ]);
    assert!(result.is_ok());
    match result {
        Ok(arg_matches) => {
            assert_eq!(arg_matches.value_of_os("flag"), Some(OsStr::new("标记2")));
            assert_eq!(arg_matches.value_of_os("other"), Some(OsStr::new("flag=标记2")));
        }
        Err(e) => println!("{}", e.to_string()),
    }
}
EOF

echo "== registering the module with the harness =="
if ! grep -q '^mod dunnage_repro;$' tests/builder/main.rs; then
  sed -i 's/^mod version;$/mod version;\nmod dunnage_repro;/' tests/builder/main.rs
fi

echo "== rebuilding the harness and proving the contract =="
cargo test --no-run -p clap
BIN=$(ls -t target/debug/deps/builder-* | grep -v '\.d$' | head -1)
"$BIN" --test default_value_ifs_os_repro
"$BIN" > /tmp/oracle-full.log 2>&1
grep -q 'test result: ok.' /tmp/oracle-full.log
echo "OK: reproduction passes and the full builder suite is green"