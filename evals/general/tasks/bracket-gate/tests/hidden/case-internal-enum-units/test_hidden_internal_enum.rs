// Hidden case for bracket-gate: an INTERNALLY tagged enum (unit variants)
// flattened inside an INTERNALLY tagged struct, with an extra plain
// non-flatten field alongside.
//
// The upstream regression test uses an adjacently tagged newtype enum and no
// other fields; this case differs in the flattened enum's flavor (internal
// tag only), the tag names, and the additional non-flatten field, so passing
// the upstream test alone does not guarantee this one.
use serde::{Deserialize, Serialize};
use serde_test::{assert_ser_tokens, Token};

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub struct Recipe {
    #[serde(flatten)]
    pub kind: Kind,
    pub servings: u32,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum Kind {
    Soup,
    Stew,
}

#[test]
fn internally_tagged_struct_with_flattened_internal_enum_plus_field() {
    assert_ser_tokens(
        &Recipe { kind: Kind::Soup, servings: 2 },
        &[
            Token::Map { len: None },
            Token::Str("type"),
            Token::Str("Recipe"),
            Token::Str("kind"),
            Token::Str("Soup"),
            Token::Str("servings"),
            Token::U32(2),
            Token::MapEnd,
        ],
    );

    assert_ser_tokens(
        &Recipe { kind: Kind::Stew, servings: 4 },
        &[
            Token::Map { len: None },
            Token::Str("type"),
            Token::Str("Recipe"),
            Token::Str("kind"),
            Token::Str("Stew"),
            Token::Str("servings"),
            Token::U32(4),
            Token::MapEnd,
        ],
    );
}