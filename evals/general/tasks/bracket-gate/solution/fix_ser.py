#!/usr/bin/env python3
"""Apply the issue-#1468 serialization fix to serde_derive/src/ser.rs.

The parent commit's code generator emits the tag field of an internally
tagged struct only in the non-flatten code path.  When the struct has a
`#[serde(flatten)]` field the code generator routes to
`serialize_struct_as_map`, which never emits the struct's own tag at all,
so the flattened value's own tag/name ends up where the outer tag belongs
(and the outer tag is missing).  This patch:

  * adds `serialize_struct_tag_field`, a single source of truth for the
    internally-tagged struct's tag entry, and
  * wires it into both `serialize_struct_as_struct` and
    `serialize_struct_as_map` (emitting the tag before the fields and
    counting it in the map length).

The result is byte-identical to the upstream fixed file, which is asserted
by a hard SHA-256 check after the edits.

Idempotent: a source that already carries the fixed helper passes with no
edits.  Fails closed (non-zero exit) if any expected snippet is missing.
"""

import hashlib
import sys
from pathlib import Path

EXPECTED_DIGEST = "9f38d2719c22b962b31ab957cdb285013c86c52b6ed1cf4eb909e9b64dfd702a"

REPLACEMENTS = [
    # 1. serialize_struct_as_struct: replace the insert-at-index-0 block
    #    with the shared tag-field helper call.
    (
        """    let mut serialize_fields =
        serialize_struct_visitor(fields, params, false, &StructTrait::SerializeStruct);

    let type_name = cattrs.name().serialize_name();

    let additional_field_count: usize = match *cattrs.tag() {
        attr::TagType::Internal { ref tag } => {
            let func = StructTrait::SerializeStruct.serialize_field(Span::call_site());
            serialize_fields.insert(
                0,
                quote! {
                    try!(#func(&mut __serde_state, #tag, #type_name));
                },
            );

            1
        }
        _ => 0,
    };
""",
        """    let serialize_fields =
        serialize_struct_visitor(fields, params, false, &StructTrait::SerializeStruct);

    let type_name = cattrs.name().serialize_name();

    let tag_field = serialize_struct_tag_field(cattrs, &StructTrait::SerializeStruct);
    let tag_field_exists = !tag_field.is_empty();
""",
    ),
    # 2. serialize_struct_as_struct: the state is mutable when the tag exists.
    (
        "    let let_mut = mut_if(serialized_fields.peek().is_some() || additional_field_count > 0);",
        "    let let_mut = mut_if(serialized_fields.peek().is_some() || tag_field_exists);",
    ),
    # 3. serialize_struct_as_struct: the tag counts in the field tally.
    (
        """            quote!(#additional_field_count),
""",
        """            quote!(#tag_field_exists as usize),
""",
    ),
    # 4. serialize_struct_as_struct: emit the struct's own tag first.
    (
        """    quote_block! {
        let #let_mut __serde_state = try!(_serde::Serializer::serialize_struct(__serializer, #type_name, #len));
        #(#serialize_fields)*
        _serde::ser::SerializeStruct::end(__serde_state)
    }
""",
        """    quote_block! {
        let #let_mut __serde_state = try!(_serde::Serializer::serialize_struct(__serializer, #type_name, #len));
        #tag_field
        #(#serialize_fields)*
        _serde::ser::SerializeStruct::end(__serde_state)
    }
""",
    ),
    # 5. insert the shared helper before serialize_struct_as_struct.
    (
        "fn serialize_struct_as_struct(\n",
        """fn serialize_struct_tag_field(
    cattrs: &attr::Container,
    struct_trait: &StructTrait,
) -> TokenStream {
    match *cattrs.tag() {
        attr::TagType::Internal { ref tag } => {
            let type_name = cattrs.name().serialize_name();
            let func = struct_trait.serialize_field(Span::call_site());
            quote! {
                try!(#func(&mut __serde_state, #tag, #type_name));
            }
        }
        _ => quote!{}
    }
}

fn serialize_struct_as_struct(
""",
    ),
    # 6. serialize_struct_as_map: emit the struct's own tag there too.
    (
        """    let serialize_fields =
        serialize_struct_visitor(fields, params, false, &StructTrait::SerializeMap);

    let mut serialized_fields = fields
""",
        """    let serialize_fields =
        serialize_struct_visitor(fields, params, false, &StructTrait::SerializeMap);

    let tag_field = serialize_struct_tag_field(cattrs, &StructTrait::SerializeMap);
    let tag_field_exists = !tag_field.is_empty();

    let mut serialized_fields = fields
""",
    ),
    # 7. serialize_struct_as_map: the state is mutable when the tag exists.
    (
        """    let let_mut = mut_if(serialized_fields.peek().is_some());

    let len = if cattrs.has_flatten() {
""",
        """    let let_mut = mut_if(serialized_fields.peek().is_some() || tag_field_exists);

    let len = if cattrs.has_flatten() {
""",
    ),
    # 8. serialize_struct_as_map: count the tag when the length is unfused.
    (
        """            .fold(quote!(0), |sum, expr| quote!(#sum + #expr));
        quote!(_serde::export::Some(#len))
""",
        """            .fold(
                quote!(#tag_field_exists as usize),
                |sum, expr| quote!(#sum + #expr)
            );
        quote!(_serde::export::Some(#len))
""",
    ),
    # 9. serialize_struct_as_map: emit the struct's own tag first.
    (
        """    quote_block! {
        let #let_mut __serde_state = try!(_serde::Serializer::serialize_map(__serializer, #len));
        #(#serialize_fields)*
        _serde::ser::SerializeMap::end(__serde_state)
    }
""",
        """    quote_block! {
        let #let_mut __serde_state = try!(_serde::Serializer::serialize_map(__serializer, #len));
        #tag_field
        #(#serialize_fields)*
        _serde::ser::SerializeMap::end(__serde_state)
    }
""",
    ),
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_ser.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if "fn serialize_struct_tag_field(" in src:
        # Already carries the helper; accept only if it is the exact fixed file.
        digest = hashlib.sha256(src.encode("utf-8")).hexdigest()
        if digest == EXPECTED_DIGEST:
            print(f"ok: {path} already carries the serialization fix (digest matches)")
            return 0
        print("FATAL: {path} looks fixed but differs from the reference; refusing", file=sys.stderr)
        return 1

    applied = 0
    for i, (old, new) in enumerate(REPLACEMENTS, 1):
        if old in src:
            src = src.replace(old, new, 1)
            applied += 1
        elif new in src:
            applied += 1  # already applied by a previous run
        else:
            print(f"FATAL: snippet {i} not found in source:", file=sys.stderr)
            print(old, file=sys.stderr)
            return 1

    if applied != len(REPLACEMENTS):
        print(f"FATAL: expected {len(REPLACEMENTS)} edits, applied {applied}", file=sys.stderr)
        return 1

    digest = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if digest != EXPECTED_DIGEST:
        print(f"FATAL: patched file digest {digest} != expected {EXPECTED_DIGEST}", file=sys.stderr)
        return 1

    path.write_text(src, encoding="utf-8")
    print(f"ok: applied the serialize_struct_tag_field fix to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())