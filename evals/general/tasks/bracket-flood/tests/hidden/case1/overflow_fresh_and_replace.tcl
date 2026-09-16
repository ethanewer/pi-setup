start_server {tags {"dump"}} {
    test {RESTORE refuses a huge-but-not-maximum relative TTL (fresh key)} {
        r del overflow-fresh-key
        r set overflow-fresh-key "fresh-payload"
        set enc [r dump overflow-fresh-key]
        r del overflow-fresh-key
        set ek [s expired_keys]
        assert_error "ERR invalid expire time in 'restore' command" {
            r restore overflow-fresh-key 9223372036854775000 $enc
        }
        assert_equal 0 [r exists overflow-fresh-key]
        assert_equal $ek [s expired_keys]
    }

    test {RESTORE with overflowing relative TTL on REPLACE keeps the old value} {
        r del overflow-existing
        r set overflow-existing "existing-payload"
        set enc [r dump overflow-existing]
        set ek [s expired_keys]
        assert_error "ERR invalid expire time in 'restore' command" {
            r restore overflow-existing 9223372036854770000 $enc replace
        }
        assert_equal "existing-payload" [r get overflow-existing]
        assert_equal -1 [r pttl overflow-existing]
        assert_equal $ek [s expired_keys]
        # A sane relative TTL must keep working right after the refusal.
        r restore overflow-existing 10000 $enc replace
        assert_equal "existing-payload" [r get overflow-existing]
        assert_morethan [r pttl overflow-existing] 0
    }
}