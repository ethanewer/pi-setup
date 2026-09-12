// Authored hidden case (bracket-forge): a MULTI-PATTERN one-pass DFA
// searched with far more caller slots than the compiled regex needs (2
// patterns without capture groups => 4 implicit slots; caller gives 6).
// Exercises the same slot-accounting code path as the upstream regression
// tests but from inputs they do not use: several patterns at once and a
// caller slot buffer that overflows the implicit region by two slots.
// Missing/extra slots must stay None; the matching pattern must still be
// reported with correct overall-match offsets.
#[test]
fn too_many_slots_many_patterns() {
    use regex_automata::{
        dfa::onepass::DFA, util::primitives::NonMaxUsize, Anchored, Input,
        PatternID,
    };

    let expr = DFA::new_many(&[r"ab", r"cdef"]).unwrap();
    let s = "cdef";
    let input = Input::new(s).span(0..s.len()).anchored(Anchored::Yes);

    let mut cache = expr.create_cache();
    let mut slots: Vec<Option<NonMaxUsize>> = vec![None; 6];
    let pid = expr.try_search_slots(&mut cache, &input, &mut slots).unwrap();
    assert_eq!(pid, Some(PatternID::must(1)));
    // Pattern 0's implicit start slot is initialised but it never matched,
    // so its end slot stays empty.
    assert_eq!(slots[0], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots[1], None);
    // Pattern 1 matched the whole haystack.
    assert_eq!(slots[2], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots[3], Some(NonMaxUsize::new(4).unwrap()));
    // The two leftover slots beyond the compiled regex's needs stay empty.
    assert_eq!(slots[4], None);
    assert_eq!(slots[5], None);

    // Also exercise the same DFA from the other direction: the second
    // pattern's anchor must not confuse a search that matches the first.
    let s2 = "abx";
    let input2 = Input::new(s2).span(0..3).anchored(Anchored::Yes);
    let mut slots2: Vec<Option<NonMaxUsize>> = vec![None; 6];
    let pid2 =
        expr.try_search_slots(&mut cache, &input2, &mut slots2).unwrap();
    assert_eq!(pid2, Some(PatternID::must(0)));
    assert_eq!(slots2[0], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots2[1], Some(NonMaxUsize::new(2).unwrap()));
    assert_eq!(slots2[2], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots2[3], None);
    assert_eq!(slots2[4], None);
    assert_eq!(slots2[5], None);
}