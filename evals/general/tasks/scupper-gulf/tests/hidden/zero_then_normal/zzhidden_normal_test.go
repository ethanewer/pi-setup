// scupper-gulf hidden case 3: after a zero-count request is accepted, a
// subsequent NORMAL (non-zero-count) request on the same connection must
// still be served; the dispatcher must not be left in a state where only
// zero-count requests work. Uses Size 42, which the upstream regression test
// never combines with a preceding zero-count request.
package protocol

import (
	"testing"
	"time"

	"github.com/syncthing/syncthing/internal/gen/bep"
	"github.com/syncthing/syncthing/lib/testutil"
)

func TestHiddenZeroThenNormal(t *testing.T) {
	m := newTestModel()
	rw := testutil.NewBlockingRW()
	c := getRawConnection(NewConnection(c0ID, rw, &testutil.NoopRW{}, testutil.NoopCloser{}, m, new(mockedConnectionInfo), CompressionAlways, testKeyGen))
	c.Start()
	defer closeAndWait(c, rw)

	c.inbox <- &bep.ClusterConfig{}

	c.inbox <- &bep.Request{Id: 21, Name: "empty.dat", Size: 0}
	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 21 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated on the zero-count request")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}

	c.inbox <- &bep.Request{Id: 22, Name: "valid", Size: 42}
	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 22 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated on the normal request")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}
}