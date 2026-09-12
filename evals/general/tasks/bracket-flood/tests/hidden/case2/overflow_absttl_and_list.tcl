start_server {tags {"dump"}} {
    test {A huge absolute TTL (ABSTTL) still creates a live key} {
        r del overflow-absttl
        r set overflow-absttl "absttl-payload"
        set enc [r dump overflow-absttl]
        r del overflow-absttl
        set ek [s expired_keys]
        assert_equal OK [r restore overflow-absttl 9223372036854774000 $enc absttl]
        assert_equal 1 [r exists overflow-absttl]
        assert_morethan [r pttl overflow-absttl] 0
        assert_equal $ek [s expired_keys]
    }

    test {huge relative TTL on a list-typed serialized value is refused} {
        r del overflow-list
        r rpush overflow-list a b c
        set enc [r dump overflow-list]
        r del overflow-list
        assert_error "ERR invalid expire time in 'restore' command" {
            r restore overflow-list 9223372036854775807 $enc
        }
        assert_equal 0 [r exists overflow-list]
    }
}