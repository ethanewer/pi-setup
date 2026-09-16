use uv_client::{DataWithCachePolicy, ErrorKind};

#[test]
fn reject_overflowing_cache_policy_len_max_with_short_payload() {
    // 3 bytes of payload data followed by a 0xFF x8 length marker: a
    // corrupted real-world entry whose body precedes the overflowing marker.
    let error = DataWithCachePolicy::from_reader(&[0xAA, 0xAA, 0xAA, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF][..]).unwrap_err();
    assert!(matches!(error.kind(), ErrorKind::ArchiveRead(_)));
}

#[test]
fn reject_overflowing_cache_policy_len_max_with_long_payload() {
    // 8 bytes of payload data followed by a 0xFF x8 length marker.
    let error = DataWithCachePolicy::from_reader(&[0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF][..]).unwrap_err();
    assert!(matches!(error.kind(), ErrorKind::ArchiveRead(_)));
}