use uv_client::{DataWithCachePolicy, ErrorKind};

#[test]
fn reject_overflowing_cache_policy_len_max_minus_seven() {
    // Trailing marker decodes to usize::MAX - 7 (0xF8 FF FF FF FF FF FF FF):
    // adding 8 wraps to 0, so an unchecked size guard can never fire; the
    // reader must reject the entry as an ArchiveRead error, not panic.
    let error = DataWithCachePolicy::from_reader(&[0xF8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF][..]).unwrap_err();
    assert!(matches!(error.kind(), ErrorKind::ArchiveRead(_)));
}

#[test]
fn reject_overflowing_cache_policy_len_max_minus_one() {
    // Trailing marker decodes to usize::MAX - 1 (0xFE FF FF FF FF FF FF FF):
    // adding 8 wraps to 6.
    let error = DataWithCachePolicy::from_reader(&[0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF][..]).unwrap_err();
    assert!(matches!(error.kind(), ErrorKind::ArchiveRead(_)));
}