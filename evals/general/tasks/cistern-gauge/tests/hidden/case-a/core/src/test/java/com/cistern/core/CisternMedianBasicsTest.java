package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden grading fixture (case-a, cistern-core). The baseline strategy must
 * estimate the MEDIAN of the window's samples. Covers the classic cut points
 * the shipped suite does not: even-sized windows, unsorted input, duplicate
 * values, negatives, and the untouched neighbours (SampleWindow.mean and the
 * other strategies).
 */
class CisternMedianBasicsTest {

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
    void evenSizedWindowAveragesTheTwoMiddleValues() {
        // sorted {1, 2, 3, 4} -> (2 + 3) / 2 = 2.5 of capacity 1000
        assertEquals(0.0025, assessor.assess(window(1.0, 2.0, 3.0, 4.0), THRESHOLD), 1e-9);
    }

    @Test
    void unsortedWindowStillReturnsTheMedian() {
        // sorted {1, 2, 5, 7, 9} -> 5
        assertEquals(0.005, assessor.assess(window(9.0, 2.0, 5.0, 1.0, 7.0), THRESHOLD), 1e-9);
    }

    @Test
    void duplicatesAreKeptInTheSortedRun() {
        assertEquals(0.004, assessor.assess(window(4.0, 4.0, 9.0), THRESHOLD), 1e-9);
    }

    @Test
    void negativeValuesSaturateTheLevelWithoutDistortingTheMedian() {
        // median of {-3, 0, 2} is 0
        assertEquals(0.0, assessor.assess(window(-3.0, 0.0, 2.0), THRESHOLD), 1e-9);
    }

    @Test
    void levelIsSaturatedIntoTheBand() {
        // median 4000 of capacity 1000 saturates at 1.0
        assertEquals(1.0, assessor.assess(window(3000.0, 4000.0, 5000.0), THRESHOLD), 1e-9);
    }

    @Test
    void modelLevelWindowMeanStaysArithmetic() {
        // the model-layer mean must NOT have been redefined to a median
        assertEquals(26.5, window(1.0, 2.0, 3.0, 100.0).mean(), 1e-9);
    }

    @Test
    void otherStrategiesKeepTheirEstimators() {
        assertEquals(0.8, new PeakAssessor().assess(window(100.0, 800.0, 400.0), THRESHOLD), 1e-9);
        assertEquals("peak", new PeakAssessor().code());
    }

    @Test
    void codeSurvivesAndDescriptionMentionsTheMedian() {
        assertEquals("baseline", assessor.code());
        assertTrue(assessor.describe().toLowerCase().contains("median"));
    }
}