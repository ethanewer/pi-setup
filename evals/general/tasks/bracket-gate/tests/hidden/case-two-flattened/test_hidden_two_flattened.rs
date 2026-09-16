// Hidden case for bracket-gate: an INTERNALLY tagged struct with TWO
// flattened fields, one an internally tagged enum and one an adjacently
// tagged enum, serialized together into the same map.
//
// The upstream regression test has a single flattened field; this case
// differs in exercising the same code path with two flattened tagged values
// and no other fields, so passing the upstream test alone does not guarantee
// this one.
use serde::{Deserialize, Serialize};
use serde_test::{assert_ser_tokens, Token};

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "outer")]
pub struct Both {
    #[serde(flatten)]
    pub a: Left,
    #[serde(flatten)]
    pub b: Right,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "left")]
pub enum Left {
    U,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "right", content = "value")]
pub enum Right {
    W(u64),
}

#[test]
fn two_flattened_tagged_enums_keep_outer_struct_tag() {
    assert_ser_tokens(
        &Both { a: Left::U, b: Right::W(5) },
        &[
            Token::Map { len: None },
            Token::Str("outer"),
            Token::Str("Both"),
            Token::Str("left"),
            Token::Str("U"),
            Token::Str("right"),
            Token::Str("W"),
            Token::Str("value"),
            Token::U64(5),
            Token::MapEnd,
        ],
    );
}