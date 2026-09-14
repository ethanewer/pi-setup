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
// Authored hidden case for topsail-deepwater. Exercises the unknown-sample-type
// error path of formatSeriesSet from stream positions the upstream companion
// test (TestFormatSeriesSetRejectsUnknownSampleType) does not use: an unknown
// value type appearing MID-STREAM after a valid float, and a different raw
// value appearing from the very first position. The buggy dump neither reports
// these values nor returns an error.

package main

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/prometheus/prometheus/model/histogram"
	"github.com/prometheus/prometheus/model/labels"
	"github.com/prometheus/prometheus/storage"
	"github.com/prometheus/prometheus/tsdb/chunkenc"
	"github.com/prometheus/prometheus/util/annotations"
)

func TestHiddenUnknownTypeMidStream(t *testing.T) {
	ss := &zzMidSeriesSet{
		series: &storage.SeriesEntry{
			Lset: labels.FromStrings(labels.MetricName, "mid_unknown"),
			SampleIteratorFn: func(chunkenc.Iterator) chunkenc.Iterator {
				return &zzMidUnknownIterator{}
			},
		},
	}

	// A valid float is drained and printed, then the iterator yields an
	// unrecognized value type: the formatter must surface an explicit error
	// instead of silently stopping.
	require.EqualError(t, formatSeriesSet(ss), "unknown sample type unknown")
}

func TestHiddenUnknownTypeFirst(t *testing.T) {
	ss := &zzMidSeriesSet{
		series: &storage.SeriesEntry{
			Lset: labels.FromStrings(labels.MetricName, "first_unknown"),
			SampleIteratorFn: func(chunkenc.Iterator) chunkenc.Iterator {
				return &zzFirstUnknownIterator{}
			},
		},
	}

	require.EqualError(t, formatSeriesSet(ss), "unknown sample type unknown")
}

type zzMidSeriesSet struct {
	series storage.Series
	done   bool
}

func (s *zzMidSeriesSet) Next() bool {
	if s.done {
		return false
	}
	s.done = true
	return true
}

func (s *zzMidSeriesSet) At() storage.Series { return s.series }
func (*zzMidSeriesSet) Err() error                        { return nil }
func (*zzMidSeriesSet) Warnings() annotations.Annotations { return nil }

// Yields ValFloat, then an unrecognized raw value type, then ValNone.
type zzMidUnknownIterator struct {
	chunkenc.Iterator
	step int
}

func (it *zzMidUnknownIterator) Next() chunkenc.ValueType {
	switch it.step {
	case 0:
		it.step = 1
		return chunkenc.ValFloat
	case 1:
		it.step = 2
		return chunkenc.ValueType(253)
	default:
		return chunkenc.ValNone
	}
}

func (it *zzMidUnknownIterator) At() (int64, float64) { return int64(0), 1.5 }
func (*zzMidUnknownIterator) Seek(t int64) chunkenc.ValueType            { return chunkenc.ValNone }
func (*zzMidUnknownIterator) AtT() int64                                  { return 0 }
func (*zzMidUnknownIterator) AtST() int64                                 { return 0 }
func (*zzMidUnknownIterator) Err() error                                  { return nil }
func (*zzMidUnknownIterator) AtHistogram(*histogram.Histogram) (int64, *histogram.Histogram)         { return int64(0), nil }
func (*zzMidUnknownIterator) AtFloatHistogram(*histogram.FloatHistogram) (int64, *histogram.FloatHistogram) { return int64(0), nil }

// Yields an unrecognized raw value type immediately.
type zzFirstUnknownIterator struct {
	chunkenc.Iterator
	done bool
}

func (it *zzFirstUnknownIterator) Next() chunkenc.ValueType {
	if it.done {
		return chunkenc.ValNone
	}
	it.done = true
	return chunkenc.ValueType(254)
}

func (it *zzFirstUnknownIterator) At() (int64, float64) { return int64(0), 0 }
func (*zzFirstUnknownIterator) Seek(t int64) chunkenc.ValueType            { return chunkenc.ValNone }
func (*zzFirstUnknownIterator) AtT() int64                                  { return 0 }
func (*zzFirstUnknownIterator) AtST() int64                                 { return 0 }
func (*zzFirstUnknownIterator) Err() error                                  { return nil }
func (*zzFirstUnknownIterator) AtHistogram(*histogram.Histogram) (int64, *histogram.Histogram)         { return int64(0), nil }
func (*zzFirstUnknownIterator) AtFloatHistogram(*histogram.FloatHistogram) (int64, *histogram.FloatHistogram) { return int64(0), nil }