// Copyright The Prometheus Authors
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Authored hidden case for topsail-deepwater. Exercises the same
// formatSeriesSet dump path as the upstream regression test
// (TestTSDBDumpNativeHistogram) but with inputs that test does not use:
// a five-sample pure-histogram series, a series whose float/histogram layout
// ends on a histogram run of two, non-1-based bucket counts, and a plain
// float-only series as a no-regression guard. The buggy dump drops the first
// sample(s) of each histogram run; a correct dump must contain every sample.

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

func TestHiddenInterleaveDumpCompleteness(t *testing.T) {
	st := promqltest.LoadedStorage(t, `
		load 1m
			blend{job="h"} 1 2 {{sum:3 count:3}} 4 {{sum:5 count:5}} {{sum:6 count:6}}
			plain{job="h"} 100 200 300
	`)

	app := st.AppenderV2(context.Background())

	for i := range 5 {
		_, err := app.Append(
			0,
			labels.FromStrings(labels.MetricName, "deep5", "job", "h"),
			0,
			int64(i) * int64(time.Minute / time.Millisecond),
			0,
			&histogram.Histogram{
				Count:         uint64(i + 6),
				Sum:           float64(i + 6) * 10,
				ZeroCount:     uint64(i + 6),
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
{__name__="blend", job="h"} 1 0
{__name__="blend", job="h"} 2 60000
{__name__="blend", job="h"} {count:3, sum:3} 120000
{__name__="blend", job="h"} 4 180000
{__name__="blend", job="h"} {count:5, sum:5} 240000
{__name__="blend", job="h"} {count:6, sum:6} 300000
{__name__="deep5", job="h"} {count:6, sum:60, [-0.001,0.001]:6} 0
{__name__="deep5", job="h"} {count:7, sum:70, [-0.001,0.001]:7} 60000
{__name__="deep5", job="h"} {count:8, sum:80, [-0.001,0.001]:8} 120000
{__name__="deep5", job="h"} {count:9, sum:90, [-0.001,0.001]:9} 180000
{__name__="deep5", job="h"} {count:10, sum:100, [-0.001,0.001]:10} 240000
{__name__="plain", job="h"} 100 0
{__name__="plain", job="h"} 200 60000
{__name__="plain", job="h"} 300 120000
`
	require.Equal(t, sortLines(strings.TrimSpace(expected)), sortLines(strings.TrimSpace(dumped)))
}