// Authored hidden case (bracket-forge): a UTF-8 pattern WITH an empty match
// (`a*`) searched with more caller slots than the compiled regex needs. This
// takes the `utf8empty` special path in `try_search_slots` before reaching
// the ordinary search loop, which the upstream regression tests do not
// exercise. The search must succeed and leave the excess slots empty.
#[test]
fn too_many_slots_empty_match_pattern() {
    use regex_automata::{
        dfa::onepass::DFA, util::primitives::NonMaxUsize, Anchored, Input,
    };

    let expr = DFA::new(r"a*").unwrap();
    let s = "aaa";
    let input = Input::new(s).span(0..s.len()).anchored(Anchored::Yes);

    let mut cache = expr.create_cache();
    let mut slots: Vec<Option<NonMaxUsize>> = vec![None; 4];
    let pid = expr.try_search_slots(&mut cache, &input, &mut slots).unwrap();
    assert_eq!(pid, Some(regex_automata::PatternID::must(0)));
    assert_eq!(slots[0], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots[1], Some(NonMaxUsize::new(3).unwrap()));
    // No capture groups at all: the two leftover slots stay empty.
    assert_eq!(slots[2], None);
    assert_eq!(slots[3], None);

    // Empty haystack: the empty match must be reported, not a panic, even
    // with surplus caller slots.
    let input2 = Input::new("").span(0..0).anchored(Anchored::Yes);
    let mut slots2: Vec<Option<NonMaxUsize>> = vec![None; 4];
    let pid2 =
        expr.try_search_slots(&mut cache, &input2, &mut slots2).unwrap();
    assert_eq!(pid2, Some(regex_automata::PatternID::must(0)));
    assert_eq!(slots2[0], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots2[1], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots2[2], None);
    assert_eq!(slots2[3], None);
}