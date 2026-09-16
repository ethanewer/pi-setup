// Hidden case for bracket-gate: an ADJACENTLY tagged enum (tag + content)
// whose variants have several different payload shapes (newtype with u64,
// newtype with i8, and a unit variant) flattened inside an INTERNALLY tagged
// struct, plus a plain non-flatten field.
//
// The upstream regression test exercises only a single u64 newtype variant
// and no other fields; this case differs in the variant shapes, the tag
// names and the extra field, so passing the upstream test alone does not
// guarantee this one.
use serde::{Deserialize, Serialize};
use serde_test::{assert_ser_tokens, Token};

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "tag_struct")]
pub struct Envelope {
    #[serde(flatten)]
    pub payload: Payload,
    pub seq: u64,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "ptype", content = "payload")]
pub enum Payload {
    Num(u64),
    Small(i8),
    Nothing,
}

#[test]
fn flatten_adjacent_enum_variants_keep_struct_tag() {
    assert_ser_tokens(
        &Envelope { payload: Payload::Num(7), seq: 1 },
        &[
            Token::Map { len: None },
            Token::Str("tag_struct"),
            Token::Str("Envelope"),
            Token::Str("ptype"),
            Token::Str("Num"),
            Token::Str("payload"),
            Token::U64(7),
            Token::Str("seq"),
            Token::U64(1),
            Token::MapEnd,
        ],
    );

    assert_ser_tokens(
        &Envelope { payload: Payload::Small(3), seq: 2 },
        &[
            Token::Map { len: None },
            Token::Str("tag_struct"),
            Token::Str("Envelope"),
            Token::Str("ptype"),
            Token::Str("Small"),
            Token::Str("payload"),
            Token::I8(3),
            Token::Str("seq"),
            Token::U64(2),
            Token::MapEnd,
        ],
    );

    assert_ser_tokens(
        &Envelope { payload: Payload::Nothing, seq: 3 },
        &[
            Token::Map { len: None },
            Token::Str("tag_struct"),
            Token::Str("Envelope"),
            Token::Str("ptype"),
            Token::Str("Nothing"),
            Token::Str("seq"),
            Token::U64(3),
            Token::MapEnd,
        ],
    );
}