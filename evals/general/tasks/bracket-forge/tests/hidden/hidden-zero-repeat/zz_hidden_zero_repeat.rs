// Authored hidden case (bracket-forge): the never-participating group is
// NOT the last group and sits amid other capture groups, with a caller slot
// buffer far larger than the compiled regex needs. (`(y){0}` means EXACTLY
// zero repetitions, so the compiled one-pass DFA accepts "xz" and the `y`
// can never appear; its slots and every slot beyond the compiled groups must
// stay None while the participating groups hold exact offsets.) Exercises
// the same slot-accounting code path as the upstream regression test
// `zero_repetition_capture_group` but with a different pattern shape: a
// zero-repeat group BETWEEN two participating groups.
#[test]
fn zero_repetition_group_between_groups() {
    use regex_automata::{
        dfa::onepass::DFA, util::primitives::NonMaxUsize, Anchored, Input,
    };

    // 3 groups in the concrete syntax: (x), (y){0}, (z); the DFA matches xz.
    let expr = DFA::new(r"(x)(y){0}(z)").unwrap();
    let s = "xz";
    let input = Input::new(s).span(0..s.len()).anchored(Anchored::Yes);

    // 8 groups' worth of slots (16) -- far more than the compiled regex's
    // explicit slots.
    let mut cache = expr.create_cache();
    let mut slots: Vec<Option<NonMaxUsize>> = vec![None; 16];
    let pid = expr.try_search_slots(&mut cache, &input, &mut slots).unwrap();
    assert_eq!(pid, Some(regex_automata::PatternID::must(0)));
    // Overall match.
    assert_eq!(slots[0], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots[1], Some(NonMaxUsize::new(2).unwrap()));
    // (x) participated: 0..1.
    assert_eq!(slots[2], Some(NonMaxUsize::new(0).unwrap()));
    assert_eq!(slots[3], Some(NonMaxUsize::new(1).unwrap()));
    // (z) participated: 1..2.
    assert_eq!(slots[6], Some(NonMaxUsize::new(1).unwrap()));
    assert_eq!(slots[7], Some(NonMaxUsize::new(2).unwrap()));
    // The never-participating (y){0} region and every further padding
    // slot (beyond the compiled regex's needs) must all be None.
    assert_eq!(slots[4], None);
    assert_eq!(slots[5], None);
    for i in 8..16 {
        assert_eq!(slots[i], None);
    }
}