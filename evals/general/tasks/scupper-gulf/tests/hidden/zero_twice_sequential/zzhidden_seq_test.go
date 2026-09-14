// scupper-gulf hidden case 2: the connection must survive TWO consecutive
// zero-count block requests (the upstream regression test only sends one, so
// a fix that tears the connection down after one accepted zero request would
// pass upstream's test but fail here).
package protocol

import (
	"testing"
	"time"

	"github.com/syncthing/syncthing/internal/gen/bep"
	"github.com/syncthing/syncthing/lib/testutil"
)

func TestHiddenZeroTwiceSequential(t *testing.T) {
	m := newTestModel()
	rw := testutil.NewBlockingRW()
	c := getRawConnection(NewConnection(c0ID, rw, &testutil.NoopRW{}, testutil.NoopCloser{}, m, new(mockedConnectionInfo), CompressionAlways, testKeyGen))
	c.Start()
	defer closeAndWait(c, rw)

	c.inbox <- &bep.ClusterConfig{}

	c.inbox <- &bep.Request{Id: 11, Name: "empty-a", Size: 0}
	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 11 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated on the first zero-count request")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}

	c.inbox <- &bep.Request{Id: 12, Name: "empty-b", Size: 0}
	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 12 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated on the second zero-count request")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}
}