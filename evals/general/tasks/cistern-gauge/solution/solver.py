#!/usr/bin/env python3
"""Oracle solver for cistern-gauge.

Applies the requested behaviour change to the shipped reactor: the baseline
level strategy must estimate the median of the window instead of the
arithmetic mean, and the stale shipped test plus the user-visible description
must be brought in line with the new semantics.

The reactor ships WITH the old (mean) behaviour, so the change is implemented
as a precise pair of file rewrites against their shipped structure:

  - BaselineAssessor.java  : estimator switched to the median (even-sized
                             windows average the two middle sorted values),
                             describe() and javadoc updated, public API
                             untouched.
  - BaselineAssessorTest.java: expectations updated to the median numbers,
                             describe() assertion updated to "median".

Usage: python3 solver.py /app/pom.xml
"""

import sys
from pathlib import Path

FIXED_ASSESSOR = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Baseline level strategy.
 *
 * <p>The baseline strategy measures how full a reservoir is by comparing the
 * central tendency of the captured window with the reservoir capacity. The
 * estimator used as the central tendency is the <strong>median</strong> of
 * the sample values: the middle value of the sorted window, or - for an
 * even-sized window - the arithmetic mean of the two middle values.
 *
 * <p>This is the default strategy: the {@link AssessorRegistry} falls back to
 * it whenever a configuration names an unknown code. Because so much of the
 * stack keys off this behaviour, the estimator choice is deliberately
 * isolated inside {@link #centralEstimate(double[])}, so the strategy's public
 * contract stays stable while the estimator can evolve.
 */
public final class BaselineAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        double central = centralEstimate(window.valuesLitres());
        return LevelMath.clamp01(central / threshold.capacity());
    }

    @Override
    public String code() {
        return "baseline";
    }

    @Override
    public String describe() {
        return "Baseline level estimate (median of window)";
    }

    /**
     * Central tendency of the window values used as the baseline estimate.
     * The operation is the median of the values: the middle element of the
     * sorted window, or the arithmetic mean of the two middle elements when
     * the window has even size. Empty windows estimate 0.
     *
     * @param values litre-normalised sample values, in capture order
     * @return the central tendency of the values
     */
    private static double centralEstimate(double[] values) {
        if (values.length == 0) {
            return 0.0;
        }
        double[] sorted = values.clone();
        java.util.Arrays.sort(sorted);
        int middle = sorted.length / 2;
        if ((sorted.length & 1) == 1) {
            return sorted[middle];
        }
        return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
}
'''

FIXED_TEST = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Baseline strategy coverage: pins the median estimator and the level clamp
 * against the standard 1000-litre threshold.
 */
class BaselineAssessorTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final BaselineAssessor assessor = new BaselineAssessor();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void medianOfEvenWindowAveragesMiddleValues() {
        // median of {1, 2, 3, 100} is (2 + 3) / 2 = 2.5 -> level 0.0025
        assertEquals(0.0025, assessor.assess(window(1.0, 2.0, 3.0, 100.0), THRESHOLD), 1e-9);
    }

    @Test
    void medianOfOddWindowIsTheMiddleElement() {
        // median of {10, 35, 45} is 35 of capacity 1000 -> level 0.035
        assertEquals(0.035, assessor.assess(window(10.0, 35.0, 45.0), THRESHOLD), 1e-9);
    }

    @Test
    void medianIgnoresInputOrder() {
        assertEquals(0.035, assessor.assess(window(45.0, 10.0, 35.0), THRESHOLD), 1e-9);
    }

    @Test
    void singleSampleLevelIsItsShareOfCapacity() {
        assertEquals(0.25, assessor.assess(window(250.0), THRESHOLD), 1e-9);
    }

    @Test
    void medianOfMixedUnitsNormalisesToLitres() {
        SampleWindow mixed = SampleWindow.of(
                Sample.litres(1L, 400.0),
                Sample.of(2L, 400.0, com.cistern.model.Units.MILLILITRES, "probe"),
                Sample.litres(3L, 400.0));
        // median is 400 litres -> level 0.4
        assertEquals(0.4, assessor.assess(mixed, THRESHOLD), 1e-9);
    }

    @Test
    void emptyWindowIsZero() {
        assertEquals(0.0, assessor.assess(SampleWindow.of(), THRESHOLD), 1e-9);
    }

    @Test
    void levelsClampAtCapacity() {
        assertEquals(1.0, assessor.assess(window(1100.0, 1300.0), THRESHOLD), 1e-9);
    }

    @Test
    void exposesStableCodeAndDescription() {
        assertEquals("baseline", assessor.code());
        assertTrue(assessor.describe().contains("median"));
    }
}
'''


def repo_root(pom: Path) -> Path:
    return pom.resolve().parent


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: solver.py <reactor-pom>", file=sys.stderr)
        return 2
    root = repo_root(Path(sys.argv[1]))
    assessor = root / "cistern-core/src/main/java/com/cistern/core/BaselineAssessor.java"
    test = root / "cistern-core/src/test/java/com/cistern/core/BaselineAssessorTest.java"
    for path in (assessor, test):
        if not path.exists():
            print("solver: expected file missing: " + str(path), file=sys.stderr)
            return 1
    assessor.write_text(FIXED_ASSESSOR, encoding="utf-8")
    test.write_text(FIXED_TEST, encoding="utf-8")
    print("solver: rewrote BaselineAssessor.java and BaselineAssessorTest.java")
    return 0


if __name__ == "__main__":
    sys.exit(main())