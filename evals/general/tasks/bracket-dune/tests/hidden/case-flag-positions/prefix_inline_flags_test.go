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
// Authored hidden case for bracket-dune. Exercises the same Matcher.Prefix()
// contract as the upstream regression test but from the MatchRegexp side and
// with inline case-insensitive flags in positions the upstream test does not
// use. The upstream test only covers the single pattern `(?i)abc.+` with
// MatchNotRegexp.

package labels

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// TestHiddenInlineFlagMatchers: every matcher whose leading literal is marked
// case-insensitive must refuse to advertise a byte-for-byte prefix, no matter
// how the inline flag is placed.
func TestHiddenInlineFlagMatchers(t *testing.T) {
	patterns := []string{
		"(?i)foo.+bar|(?i)foo.*baz",
		"(?i)^abc.+",
		"(?i)ab(cd|ef).+",
		"(?i)xyz.+",
	}
	for _, v := range patterns {
		matcher := mustNewMatcher(t, MatchRegexp, v)
		t.Run(matcher.String(), func(t *testing.T) {
			require.Equal(t, "", matcher.Prefix())
			require.True(t, matcher.hasCaseInsensitivePrefix())
		})
	}
}

// TestHiddenFoldMatches: suppressing the byte-wise prefix must not change the
// case-insensitive matching itself, and a genuinely case-sensitive leading
// literal must keep being reported because it is byte-for-byte reliable.
func TestHiddenFoldMatches(t *testing.T) {
	matcher := mustNewMatcher(t, MatchRegexp, "(?i)abc.+")
	require.True(t, matcher.Matches("ABcdef"))
	require.True(t, matcher.Matches("ABCDEF"))
	require.True(t, matcher.Matches("abcdef"))
	require.False(t, matcher.Matches("xABCD"))
	require.False(t, matcher.Matches("ABC"))

	exact := mustNewMatcher(t, MatchRegexp, "(?i)abc")
	require.True(t, exact.Matches("AbC"))
	require.False(t, exact.Matches("xabc"))

	leading := mustNewMatcher(t, MatchRegexp, "a(?i)bc.+")
	require.Equal(t, "a", leading.Prefix())
	require.True(t, leading.Matches("aBcdef"))
	require.True(t, leading.Matches("aBCdEf"))
	require.False(t, leading.Matches("Abcdef"))
}