#!/bin/bash
# scupper-gulf oracle: apply the real fix to the working tree and add an own
# failing reproduction test, exactly as a successful agent would.
#   - lib/protocol/protocol.go: the dispatcher rejected every request with
#     Size <= 0 as a protocol error; zero-count requests (sent by current
#     versions for the blocks of empty files) must be accepted, only strictly
#     negative sizes remain protocol violations.
#   - lib/protocol/protocol_test.go: append an own regression test that fails
#     on the unfixed gate and passes on the fixed one.
set -u
cd /app/src || exit 1

FIX='if msg.Size <= 0 {'
FIXED='if msg.Size < 0 {'
if ! grep -qF "$FIXED" lib/protocol/protocol.go; then
  grep -qF "$FIX" lib/protocol/protocol.go || { echo "protocol.go gate not found" >&2; exit 1; }
  sed -i "s/${FIX//\//\\/}/${FIXED//\//\\/}/" lib/protocol/protocol.go
fi

if ! grep -q "func TestZeroByteRequestAccepted" lib/protocol/protocol_test.go; then
  cat >> lib/protocol/protocol_test.go <<'EOF'

func TestZeroByteRequestAccepted(t *testing.T) {
	m := newTestModel()
	rw := testutil.NewBlockingRW()
	c := getRawConnection(NewConnection(c0ID, rw, &testutil.NoopRW{}, testutil.NoopCloser{}, m, new(mockedConnectionInfo), CompressionAlways, testKeyGen))
	c.Start()
	defer closeAndWait(c, rw)

	c.inbox <- &bep.ClusterConfig{}
	c.inbox <- &bep.Request{
		Id:   9,
		Name: "zero.dat",
		Size: 0,
	}

	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 9 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated, expected zero-sized request to be accepted")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}
}
EOF
fi

# The one-line fix changed a protocol semantic (size 0 became valid) that the
# parent's own protocol_test.go still asserts as invalid in TestRequestMaxSize,
# so the FULL suite cannot be green until the regression test file is updated
# too - which is exactly what the golden file (extracted from the fix commit)
# contains and what the verifier runs against. Here in the oracle we only need
# to prove our own reproduction now passes.
go test ./lib/protocol/ -run TestZeroByteRequestAccepted -v || { echo "own reproduction did not pass" >&2; exit 1; }
exit 0