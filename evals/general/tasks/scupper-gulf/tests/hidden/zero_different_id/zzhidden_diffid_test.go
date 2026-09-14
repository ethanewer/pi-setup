// scupper-gulf hidden case 1: a zero-count block request with a request id
// and file name different from the upstream regression test's (Id 1 / "valid")
// must still be accepted and answered with a matching reply.
package protocol

import (
	"testing"
	"time"

	"github.com/syncthing/syncthing/internal/gen/bep"
	"github.com/syncthing/syncthing/lib/testutil"
)

func TestHiddenZeroDifferentId(t *testing.T) {
	m := newTestModel()
	rw := testutil.NewBlockingRW()
	c := getRawConnection(NewConnection(c0ID, rw, &testutil.NoopRW{}, testutil.NoopCloser{}, m, new(mockedConnectionInfo), CompressionAlways, testKeyGen))
	c.Start()
	defer closeAndWait(c, rw)

	c.inbox <- &bep.ClusterConfig{}
	c.inbox <- &bep.Request{
		Id:   7,
		Name: "empty-image.dat",
		Size: 0,
	}

	select {
	case res := <-c.outbox:
		if msg, ok := res.msg.(*bep.Response); !ok || msg.Id != 7 {
			t.Errorf("bad response %#v", msg)
		}
	case <-c.dispatcherLoopStopped:
		t.Fatal("dispatcher loop terminated, expected zero-sized request to be accepted")
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for response")
	}
}