# halyard-spinnaker — build notes

Working tree: real upstream `gohugoio/hugo` at the pinned parent commit
`/app/src` (shallow, detached; the fix commit is not present in the clone).

- Go 1.27.1 at `/usr/local/go`; module cache `/opt/gomodcache`, build cache
  `/opt/gocache` (both warm, world-writable).
- Pristine PRE-FIX hugo CLI: `/opt/prefix/hugo`.
- Upstream regression test (post-fix `hugolib/template_test.go`,
  `TestPartialWithZeroedArgs`): `/opt/golden/template_test.go`.
- Trust anchors (sha256): `/opt/pins/anchors.sha256`.

Common commands (offline):

    cd /app/src
    go build -o /app/hugo                          # build the CLI from the tree
    go test -vet=off ./hugolib -run TestPartialCached -v    # sample test run

The project's own `go.mod`/`go.sum` pin every dependency; GOPROXY is only
needed at image build time.