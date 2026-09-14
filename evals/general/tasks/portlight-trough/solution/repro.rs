#[macro_use]
extern crate serde_derive;

extern crate serde;
extern crate serde_test;

use serde_test::{assert_de_tokens, Token};

#[derive(Serialize, Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", content = "payload")]
enum Outcome {
    OkVariant,
    Value(u32),
}

#[test]
fn extra_map_keys_are_skipped() {
    assert_de_tokens(
        &Outcome::OkVariant,
        &[
            Token::Struct { name: "Outcome", len: 3 },
            Token::Str("trace"), Token::Str("ignored"),
            Token::Str("kind"), Token::Str("OkVariant"),
            Token::Str("payload"), Token::Unit,
            Token::StructEnd,
        ],
    );
}
