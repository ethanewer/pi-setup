#!/bin/bash
# Hidden case h3: the tag/content attribute names and every extra map key are
# generated AT VERIFIER TIME with unpredictable values ($RANDOM), so no file in
# the image or under /tests can be read in advance and special-cased. A fake
# "fix" that hardcodes the extra-key names sampled by the other tests (golden
# f,g,h; h1 meta,flag,blob,note,pad) fails here, because it cannot know these
# names. A real fix skips arbitrary unrelated keys and honors deny_unknown_fields,
# so it passes regardless of the names. Must pass on the fixed tree.
set -u
cd /app/src || exit 1

TAG="t$((RANDOM % 100000))_$((RANDOM % 100000))"
CONT="c$((RANDOM % 100000))_$((RANDOM % 100000))"
X1="x$((RANDOM % 100000))_$((RANDOM % 100000))"
X2="y$((RANDOM % 100000))_$((RANDOM % 100000))"
DY="z$((RANDOM % 100000))_$((RANDOM % 100000))"

cat > test_suite/tests/h3_random.rs <<RS
#[macro_use]
extern crate serde_derive;

extern crate serde;
extern crate serde_test;

use serde_test::{assert_de_tokens, assert_de_tokens_error, Token};

#[derive(Serialize, Deserialize, Debug, PartialEq)]
#[serde(tag = "$TAG", content = "$CONT")]
enum Gen {
    Ack,
    Item { id: u32 },
}

#[derive(Serialize, Deserialize, Debug, PartialEq)]
#[serde(tag = "$TAG", content = "$CONT", deny_unknown_fields)]
enum Strict {
    Ack,
    Item { id: u32 },
}

#[test]
fn random_extra_keys_are_skipped() {
    assert_de_tokens(
        &Gen::Ack,
        &[
            Token::Struct { name: "Gen", len: 4 },
            Token::Str("$X1"), Token::Str("v1"),
            Token::Str("$TAG"), Token::Str("Ack"),
            Token::Str("$CONT"), Token::Unit,
            Token::Str("$X2"), Token::U64(7),
            Token::StructEnd,
        ],
    );
}

#[test]
fn random_extra_key_after_content_is_skipped_for_struct_variant() {
    assert_de_tokens(
        &Gen::Item { id: 5 },
        &[
            Token::Struct { name: "Gen", len: 3 },
            Token::Str("$TAG"), Token::Str("Item"),
            Token::Str("$CONT"),
            Token::Struct { name: "Item", len: 1 },
            Token::Str("id"), Token::U32(5),
            Token::StructEnd,
            Token::Str("$DY"), Token::Bool(true),
            Token::StructEnd,
        ],
    );
}

#[test]
fn unknown_key_after_tag_errors_under_deny_unknown_fields() {
    assert_de_tokens_error::<Strict>(
        &[
            Token::Struct { name: "Strict", len: 3 },
            Token::Str("$TAG"), Token::Str("Ack"),
            Token::Str("$DY"),
        ],
        "invalid value: string \"$DY\", expected \"$TAG\" or \"$CONT\"",
    );
}
RS

if ! cargo test -p serde_test_suite --test h3_random > /tmp/h3.out 2>&1; then
    tail -25 /tmp/h3.out >&2
    exit 1
fi
grep -q "test result: ok" /tmp/h3.out || { tail -15 /tmp/h3.out >&2; exit 1; }
exit 0