package com.cistern.core;

import com.cistern.model.Assessment;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import java.util.Random;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Hidden grading fixture (case-b, cistern-core). Deeper median edge cases:
 * large shuffled windows, two-element windows, exact-capacity medians,
 * fractional ties, and the assessor's immutability guarantee.
 */
class CisternMedianEdgeTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final BaselineAssessor assessor = new BaselineAssessor();
    private final AssessmentEngine engine = new AssessmentEngine();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    private static SampleWindow shuffledRange(int count, long seed) {
        double[] values = new double[count];
        for (int i = 0; i < count; i++) {
            values[i] = i;
        }
        Random random = new Random(seed);
        for (int i = values.length - 1; i > 0; i--) {
            int j = random.nextInt(i + 1);
            double swap = values[i];
            values[i] = values[j];
            values[j] = swap;
        }
        return window(values);
    }

    @Test
    void largeOddWindowHasTheExpectedMiddle() {
        // 0..1000 shuffled -> median 500 of capacity 1000
        assertEquals(0.5, assessor.assess(shuffledRange(1001, 7L), THRESHOLD), 1e-9);
    }

    @Test
    void largeEvenWindowAveragesTheMiddlePair() {
        // 0..999 shuffled -> middle pair 499, 500 -> 499.5
        assertEquals(0.4995, assessor.assess(shuffledRange(1000, 11L), THRESHOLD), 1e-9);
    }

    @Test
    void twoElementWindowAveragesItsPair() {
        assertEquals(0.002, assessor.assess(window(1.0, 3.0), THRESHOLD), 1e-9);
    }

    @Test
    void fractionalTiesAreAveragedExactly() {
        assertEquals(0.002, assessor.assess(window(1.5, 2.5), THRESHOLD), 1e-12);
    }

    @Test
    void skewedEvenWindowFavoursTheMiddleNotTheAverage() {
        // sorted {1, 2, 3, 100} -> (2 + 3) / 2 = 2.5, not the mean 26.5
        assertEquals(0.0025, assessor.assess(window(1.0, 2.0, 3.0, 100.0), THRESHOLD), 1e-9);
    }

    @Test
    void skewedOddWindowUsesTheMiddleElement() {
        // sorted {1, 2, 3, 4, 100} -> 3, not the mean 22
        assertEquals(0.003, assessor.assess(window(1.0, 2.0, 3.0, 4.0, 100.0), THRESHOLD), 1e-9);
    }

    @Test
    void medianAtCapacityIsCriticalThroughTheEngine() {
        Assessment assessment = engine.evaluate(
                window(1000.0, 1000.0, 1000.0), THRESHOLD, "baseline");
        assertEquals(1.0, assessment.level(), 1e-9);
        assertEquals("critical", assessment.severity().code());
    }

    @Test
    void assessorDoesNotMutateTheWindow() {
        SampleWindow w = window(3.0, 1.0, 2.0);
        double[] before = w.values();
        assessor.assess(w, THRESHOLD);
        assertEquals(before[0], w.values()[0], 1e-9);
        assertEquals(before[1], w.values()[1], 1e-9);
        assertEquals(before[2], w.values()[2], 1e-9);
    }
}