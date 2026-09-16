#[macro_use]
extern crate serde_derive;

extern crate serde;
extern crate serde_test;

use serde_test::{assert_de_tokens, assert_de_tokens_error, Token};

#[derive(Serialize, Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", content = "val", deny_unknown_fields)]
enum Strict {
    Ack,
    Item { id: u32 },
}

#[test]
fn deny_unknown_fields_rejects_extra_keys() {
    assert_de_tokens_error::<Strict>(
        &[
            Token::Struct { name: "Strict", len: 3 },
            Token::Str("kind"), Token::Str("Ack"),
            Token::Str("extra"),
        ],
        "invalid value: string \"extra\", expected \"kind\" or \"val\"",
    );
}

#[test]
fn deny_unknown_fields_still_accepts_clean_map() {
    assert_de_tokens(
        &Strict::Item { id: 7 },
        &[
            Token::Struct { name: "Strict", len: 2 },
            Token::Str("kind"), Token::Str("Item"),
            Token::Str("val"),
            Token::Struct { name: "Item", len: 1 },
            Token::Str("id"), Token::U32(7),
            Token::StructEnd,
            Token::StructEnd,
        ],
    );
}
