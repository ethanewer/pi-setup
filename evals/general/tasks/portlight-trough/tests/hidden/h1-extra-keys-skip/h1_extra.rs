#[macro_use]
extern crate serde_derive;

extern crate serde;
extern crate serde_test;

use serde_test::{assert_de_tokens, Token};

#[derive(Serialize, Deserialize, Debug, PartialEq)]
#[serde(tag = "kind", content = "val")]
enum Msg {
    Ack,
    Loc { x: f64, y: f64 },
    Data(u8, u8),
}

#[test]
fn skips_map_and_seq_valued_extra_keys_around_tag_and_content() {
    assert_de_tokens(
        &Msg::Ack,
        &[
            Token::Struct { name: "Msg", len: 6 },
            Token::Str("meta"),
            Token::Map { len: Some(1) },
            Token::Str("m"), Token::U64(1),
            Token::MapEnd,
            Token::Str("kind"), Token::Str("Ack"),
            Token::Str("flag"), Token::Unit,
            Token::Str("val"), Token::Unit,
            Token::Str("blob"),
            Token::Seq { len: Some(2) },
            Token::U8(1), Token::U8(2),
            Token::SeqEnd,
            Token::StructEnd,
        ],
    );
}

#[test]
fn skips_extra_keys_when_content_comes_last_for_struct_variant() {
    assert_de_tokens(
        &Msg::Loc { x: 1.5, y: -2.5 },
        &[
            Token::Struct { name: "Msg", len: 4 },
            Token::Str("kind"), Token::Str("Loc"),
            Token::Str("note"), Token::Str("hi"),
            Token::Str("val"),
            Token::Struct { name: "Loc", len: 2 },
            Token::Str("x"), Token::F64(1.5),
            Token::Str("y"), Token::F64(-2.5),
            Token::StructEnd,
            Token::StructEnd,
        ],
    );
}

#[test]
fn skips_extras_between_content_and_tag_for_tuple_variant() {
    assert_de_tokens(
        &Msg::Data(9, 8),
        &[
            Token::Struct { name: "Msg", len: 4 },
            Token::Str("val"),
            Token::Tuple { len: 2 },
            Token::U8(9), Token::U8(8),
            Token::TupleEnd,
            Token::Str("pad"), Token::Unit,
            Token::Str("kind"), Token::Str("Data"),
            Token::StructEnd,
        ],
    );
}
