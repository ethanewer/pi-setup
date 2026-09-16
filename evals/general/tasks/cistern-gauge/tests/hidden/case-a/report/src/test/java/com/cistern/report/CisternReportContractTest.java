package com.cistern.report;

import com.cistern.core.BaselineAssessor;
import com.cistern.core.LevelAssessor;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden grading fixture (case-a, cistern-report). The report module depends
 * on the core module through the LevelAssessor interface; the median change
 * must flow through the pipeline and into rendered output while the
 * interface, the registry keys and the report schema stay intact.
 */
class CisternReportContractTest {

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
    void interfaceIsUsableThroughTheRegistry() {
        LevelAssessor assessor = pipeline.assessorFor("baseline");
        assertNotNull(assessor);
        assertTrue(assessor instanceof BaselineAssessor,
                "expected BaselineAssessor, got " + assessor.getClass().getName());
        double level = assessor.assess(window(1.0, 2.0, 3.0, 4.0), THRESHOLD);
        assertEquals(0.0025, level, 1e-9);
    }

    @Test
    void renderedReportCarriesTheMedianLevelForTheBaselineCode() {
        Map<String, Object> report = pipeline.renderMap(
                "baseline", window(9.0, 2.0, 5.0, 1.0, 7.0), THRESHOLD);
        assertEquals(0.005, ((Number) baseline(report).get("level")).doubleValue(), 1e-9);
        assertEquals("nominal", baseline(report).get("severity"));
        assertTrue(((String) baseline(report).get("method")).toLowerCase().contains("median"));
    }

    @Test
    void peakPathStillRendersUnchanged() {
        Map<String, Object> report = pipeline.renderMap(
                "peak", window(100.0, 800.0, 400.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> measures = (Map<String, Object>) report.get("measures");
        @SuppressWarnings("unchecked")
        Map<String, Object> peak = (Map<String, Object>) measures.get("peak");
        assertEquals(0.8, ((Number) peak.get("level")).doubleValue(), 1e-9);
        assertTrue(((String) peak.get("method")).contains("maximum"));
    }

    @Test
    void jsonTextContainsTheSurfacedMedian() {
        String json = pipeline.renderJson("baseline", window(1.0, 2.0, 3.0, 4.0), THRESHOLD);
        assertTrue(json.contains("0.0025"), json);
    }

    @Test
    void reportSchemaKeysAreStable() {
        Map<String, Object> report = pipeline.renderMap("baseline", window(1.0, 2.0), THRESHOLD);
        assertEquals(Set.of("header", "window", "measures", "trend"), report.keySet());
    }
}