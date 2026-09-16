package com.cistern.report;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden grading fixture (case-b, cistern-report). The median level must flow
 * through the pipeline into severity bands and rendered maps, unknown
 * strategy codes must keep their documented fallback, and the window
 * statistics block must stay untouched by the change.
 */
class CisternReportEdgesTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final ReportPipeline pipeline = new ReportPipeline();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> baseline(Map<String, Object> report) {
        Map<String, Object> measures = (Map<String, Object>) report.get("measures");
        Map<String, Object> measure = (Map<String, Object>) measures.get("baseline");
        assertNotNull(measure, "baseline measure missing from report");
        return measure;
    }

    @Test
    void warnAndAlertBandsFlowFromTheMedian() {
        Map<String, Object> warn = pipeline.renderMap(
                "baseline", window(610.0, 620.0, 630.0), THRESHOLD);
        assertEquals("warn", baseline(warn).get("severity"));
        Map<String, Object> alert = pipeline.renderMap(
                "baseline", window(900.0, 910.0, 920.0), THRESHOLD);
        assertEquals("alert", baseline(alert).get("severity"));
    }

    @Test
    void unknownStrategyCodeFallsBackToBaselineAsDocumented() {
        Map<String, Object> report = pipeline.renderMap(
                "no-such-strategy", window(1.0, 2.0, 3.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> measures = (Map<String, Object>) report.get("measures");
        assertNotNull(measures.get("baseline"));
        assertFalse(measures.containsKey("no-such-strategy"));
    }

    @Test
    void fullWindowReportsCriticalWithMedianLevelOne() {
        Map<String, Object> report = pipeline.renderMap(
                "baseline", window(2000.0, 3000.0, 4000.0), THRESHOLD);
        assertEquals(1.0, ((Number) baseline(report).get("level")).doubleValue(), 1e-9);
        assertEquals("critical", baseline(report).get("severity"));
    }

    @Test
    void windowBlockStatsAreUnaffectedByTheChange() {
        Map<String, Object> report = pipeline.renderMap(
                "baseline", window(1.0, 2.0, 3.0, 4.0, 99.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> windowBlock = (Map<String, Object>) report.get("window");
        assertEquals(21.8, ((Number) windowBlock.get("mean")).doubleValue(), 1e-9);
    }

    @Test
    void skewedMedianFlowsIntoTheRenderedMap() {
        // sorted {1, 2, 3, 100} -> median 2.5 (mean 26.5)
        Map<String, Object> report = pipeline.renderMap(
                "baseline", window(1.0, 2.0, 3.0, 100.0), THRESHOLD);
        assertEquals(0.0025, ((Number) baseline(report).get("level")).doubleValue(), 1e-9);
        assertTrue(((String) baseline(report).get("method")).toLowerCase().contains("median"));
    }

    @Test
    void labelTableStillCoversTheBaselineCode() {
        assertEquals("Baseline level", LabelTable.label("baseline"));
        assertTrue(LabelTable.label("baseline").toLowerCase().contains("level"));
    }
}