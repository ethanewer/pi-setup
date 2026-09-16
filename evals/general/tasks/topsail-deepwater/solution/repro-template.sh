#!/bin/bash
# /app/repro.sh -- authored reproduction for the promtool TSDB dump bug.
#
# Contract (see instruction.md): takes no arguments, runs entirely offline,
# drives the project's own test runner (`go test`) with a scenario test file
# authored for this bug, prints the test run output, removes the scenario file,
# and exits with the test run's exit status. Exits non-zero on a checkout that
# still has the bug (the earliest samples of histogram series are missing from
# the dump) and zero on a fixed checkout.
#
# The scenario: a series holding only histograms plus a series that interleaves
# plain numbers and histograms. A correct dump prints EVERY sample; the buggy
# dump silently drops the first sample of each histogram run.
set -u

SRC=/app/src
TESTFILE=zz_histdump_repro_test.go
LOG=/tmp/repro-go-test.log

trap 'rm -f "$SRC/cmd/promtool/$TESTFILE"' EXIT

cat > "$SRC/cmd/promtool/$TESTFILE" <<'EOF'
// Authored reproduction scenario for the promtool TSDB dump bug: a
// pure-histogram series and a float/histogram-interleaved series must both be
// dumped completely, earliest samples included.
package main

import (
	"context"
	"math"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/prometheus/prometheus/model/histogram"
	"github.com/prometheus/prometheus/model/labels"
	"github.com/prometheus/prometheus/promql/promqltest"
	"github.com/prometheus/prometheus/storage"
)

func TestZZHistDumpRepro(t *testing.T) {
	st := promqltest.LoadedStorage(t, `
		load 1m
			tide{job="deep"} 10 {{sum:7 count:7}} 20 {{sum:8 count:8}}
	`)

	app := st.AppenderV2(context.Background())

	for i := range 4 {
		_, err := app.Append(
			0,
			labels.FromStrings(labels.MetricName, "pure_h", "job", "deep"),
			0,
			int64(i) * int64(time.Minute / time.Millisecond),
			0,
			&histogram.Histogram{
				Count:         uint64(i + 1),
				Sum:           float64(i + 1),
				ZeroCount:     uint64(i + 1),
				ZeroThreshold: 0.001,
			},
			nil,
			storage.AppendV2Options{},
		)
		require.NoError(t, err)
	}
	require.NoError(t, app.Commit())

	dumped := getDumpedSamples(t, st.Dir(), "", math.MinInt64, math.MaxInt64, []string{"{__name__=~'(?s:.*)'}"}, formatSeriesSet)
	expected := `
{__name__="tide", job="deep"} 10 0
{__name__="tide", job="deep"} {count:7, sum:7} 60000
{__name__="tide", job="deep"} 20 120000
{__name__="tide", job="deep"} {count:8, sum:8} 180000
{__name__="pure_h", job="deep"} {count:1, sum:1, [-0.001,0.001]:1} 0
{__name__="pure_h", job="deep"} {count:2, sum:2, [-0.001,0.001]:2} 60000
{__name__="pure_h", job="deep"} {count:3, sum:3, [-0.001,0.001]:3} 120000
{__name__="pure_h", job="deep"} {count:4, sum:4, [-0.001,0.001]:4} 180000
`
	require.Equal(t, sortLines(strings.TrimSpace(expected)), sortLines(strings.TrimSpace(dumped)))
}
EOF

cd "$SRC"
go test -v ./cmd/promtool -run TestZZHistDumpRepro 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"