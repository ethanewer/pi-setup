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
// Authored hidden case for bracket-dune. Models the downstream consumer from
// the bug report: callers pre-filter a set of label names by comparing each
// name byte-for-byte against Prefix() and only run the full regex on the
// survivors. When the matcher is case-insensitive, the advertised prefix is
// not guaranteed to match the stored text, so that pruning loses labels the
// regex would match.

package labels

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestHiddenPrefixPruning: a prefix-driven pre-filter must never drop a label
// that the full matcher would accept.
func TestHiddenPrefixPruning(t *testing.T) {
	matcher := mustNewMatcher(t, MatchRegexp, "(?i)foo.+")

	prefix := matcher.Prefix()
	require.Equal(t, "", prefix)

	labels_set := []string{"FOOBAR", "foobar", "fOObAr", "bazqux"}

	var matched []string
	var pruned []string
	for _, s := range labels_set {
		if matcher.Matches(s) {
			matched = append(matched, s)
		}
		// The consumer-side pre-filter: byte-for-byte prefix comparison.
		if strings.HasPrefix(s, prefix) {
			pruned = append(pruned, s)
		}
	}

	// The regex matches every capitalization of the literal.
	require.Equal(t, 3, len(matched))
	require.Equal(t, labels_set, pruned)

	// Every regex match survives the pre-filter: the filter must be a
	// superset of the match set, never a subset.
	for _, s := range matched {
		require.True(t, strings.HasPrefix(s, prefix))
	}
}

// TestHiddenByteWisePrefixesKept: for genuinely case-sensitive leading
// literals the byte-wise prefix is reliable and must keep being advertised.
func TestHiddenByteWisePrefixesKept(t *testing.T) {
	cases := []struct{v, prefix string}{
		{"foobar.+", "foobar"},
		{"fOoBaR.+", "fOoBaR"},
		{"foo.+bar|foo.*baz", "foo"},
		{"abc.+" , "abc"},
		{"x(?i)abc.+", "x"},
	}
	for _, c := range cases {
		matcher := mustNewMatcher(t, MatchRegexp, c.v)
		t.Run(matcher.String(), func(t *testing.T) {
			require.Equal(t, c.prefix, matcher.Prefix())
		})
	}
}