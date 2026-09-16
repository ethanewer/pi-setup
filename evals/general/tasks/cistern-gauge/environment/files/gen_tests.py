# -*- coding: utf-8 -*-
"""Shipped JUnit 5 test sources for the cistern-gauge reactor.

Part of the cistern-gauge fixture generator.
"""

FILES = {}

T = "cistern-model/src/test/java"
FILES[f"{T}/com/cistern/model/UnitsTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UnitsTest {

    @Test
    void parsesCodesAndSymbolsCi() {
        assertEquals(Units.LITRES, Units.parse("l").orElseThrow());
        assertEquals(Units.LITRES, Units.parse("LITRES").orElseThrow());
        assertEquals(Units.GALLONS_UK, Units.parse("gal-uk").orElseThrow());
        assertEquals(Units.GALLONS_US, Units.parse("GAL-US").orElseThrow());
    }

    @Test
    void unknownUnitParsesEmpty() {
        assertEquals(Optional.empty(), Units.parse("bogus"));
        assertEquals(Optional.empty(), Units.parse(null));
        assertEquals(Optional.empty(), Units.parse(""));
    }

    @Test
    void convertsToLitres() {
        assertEquals(9.09218, Units.GALLONS_UK.toLitres(2.0), 1e-9);
        assertEquals(2000.0, Units.METRES_CUBED.toLitres(2.0), 1e-9);
        assertEquals(0.5, Units.MILLILITRES.toLitres(500.0), 1e-9);
    }

    @Test
    void roundTripsThroughLitres() {
        double value = 12.75;
        assertEquals(value, Units.GALLONS_US.fromLitres(Units.GALLONS_US.toLitres(value)), 1e-9);
        assertEquals(value, Units.BARRELS.fromLitres(Units.BARRELS.toLitres(value)), 1e-9);
    }

    @Test
    void codesAreStable() {
        assertEquals("litres", Units.LITRES.code());
        assertEquals("gallons_uk", Units.GALLONS_UK.code());
    }
}
'''

FILES[f"{T}/com/cistern/model/SampleTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class SampleTest {

    @Test
    void normalisesIntoLitres() {
        Sample sample = Sample.of(7L, 2.5, Units.GALLONS_UK, "probe-a");
        assertEquals(2.5 * 4.54609, sample.valueLitres(), 1e-9);
    }

    @Test
    void litresHelperStaysInLitres() {
        assertEquals(42.0, Sample.litres(5L, 42.0).valueLitres(), 1e-9);
    }

    @Test
    void rejectsNonFiniteValues() {
        assertThrows(IllegalArgumentException.class,
                () -> Sample.of(1L, Double.NaN, Units.LITRES, "x"));
        assertThrows(IllegalArgumentException.class,
                () -> Sample.of(1L, Double.POSITIVE_INFINITY, Units.LITRES, "x"));
    }

    @Test
    void equalityIsFull() {
        Sample a = Sample.of(1L, 2.0, Units.LITRES, "s");
        assertEquals(a, Sample.of(1L, 2.0, Units.LITRES, "s"));
        assertNotEquals(a, Sample.of(2L, 2.0, Units.LITRES, "s"));
        assertNotEquals(a, Sample.of(1L, 2.5, Units.LITRES, "s"));
        assertNotEquals(a, Sample.of(1L, 2.0, Units.GALLONS_UK, "s"));
        assertNotEquals(a, Sample.of(1L, 2.0, Units.LITRES, "other"));
    }

    @Test
    void acceptsNegativeValues() {
        Sample negative = Sample.litres(3L, -12.5);
        assertEquals(-12.5, negative.value(), 1e-9);
    }
}
'''

FILES[f"{T}/com/cistern/model/SampleWindowTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SampleWindowTest {

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void basicDescriptiveStats() {
        SampleWindow w = window(1.0, 2.0, 3.0, 4.0, 99.0);
        assertEquals(5, w.size());
        assertEquals(1.0, w.min(), 1e-9);
        assertEquals(99.0, w.max(), 1e-9);
        assertEquals(21.8, w.mean(), 1e-9);
        assertEquals(98.0, w.range(), 1e-9);
    }

    @Test
    void standardDeviationIsPopulation() {
        SampleWindow w = window(2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0);
        assertEquals(2.0, w.standardDeviation(), 1e-9);
    }

    @Test
    void standardDeviationDegradesForTinyWindows() {
        assertEquals(0.0, window(5.0).standardDeviation(), 1e-9);
        assertEquals(0.0, SampleWindow.of().standardDeviation(), 1e-9);
    }

    @Test
    void percentileUsesNearestRank() {
        SampleWindow w = window(1.0, 2.0, 3.0, 4.0, 99.0);
        assertEquals(3.0, w.percentile(50.0), 1e-9);
        assertEquals(1.0, w.percentile(0.0), 1e-9);
        assertEquals(99.0, w.percentile(100.0), 1e-9);
        assertEquals(0.0, SampleWindow.of().percentile(50.0), 1e-9);
    }

    @Test
    void subWindowKeepsSlice() {
        SampleWindow w = window(10.0, 20.0, 30.0);
        assertEquals(2, w.subWindow(0, 2).size());
        assertEquals(10.0, w.subWindow(0, 2).min(), 1e-9);
        assertEquals(20.0, w.subWindow(0, 2).max(), 1e-9);
    }

    @Test
    void valuesReturnsDefensiveCopy() {
        SampleWindow w = window(1.0, 2.0);
        w.values()[0] = 999.0;
        assertEquals(1.0, w.values()[0], 1e-9);
        assertEquals(1.0, w.min(), 1e-9);
    }

    @Test
    void chronologyIsDetected() {
        assertTrue(window(1.0, 2.0, 3.0).isChronological());
        Sample[] outOfOrder = {
                Sample.litres(30L, 1.0),
                Sample.litres(10L, 2.0),
                Sample.litres(20L, 3.0)};
        assertFalse(SampleWindow.of(outOfOrder).isChronological());
    }

    @Test
    void emptyWindowStats() {
        SampleWindow empty = SampleWindow.of();
        assertTrue(empty.isEmpty());
        assertEquals(0.0, empty.mean(), 1e-9);
        assertEquals(0.0, empty.range(), 1e-9);
    }
}
'''

FILES[f"{T}/com/cistern/model/ThresholdTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ThresholdTest {

    @Test
    void levelIsSaturatedFractionOfCapacity() {
        Threshold t = Threshold.standard(1000.0);
        assertEquals(0.5, t.levelOf(500.0), 1e-9);
        assertEquals(0.0, t.levelOf(-200.0), 1e-9);
        assertEquals(1.0, t.levelOf(2000.0), 1e-9);
    }

    @Test
    void severityBandsFromFraction() {
        Threshold t = Threshold.standard(1000.0);
        assertEquals(Severity.NOMINAL, t.severityOfFraction(0.5));
        assertEquals(Severity.WARN, t.severityOfFraction(0.6));
        assertEquals(Severity.WARN, t.severityOfFraction(0.84));
        assertEquals(Severity.ALERT, t.severityOfFraction(0.85));
        assertEquals(Severity.CRITICAL, t.severityOfFraction(1.0));
        assertEquals(Severity.CRITICAL, t.severityOfFraction(1.2));
    }

    @Test
    void rejectsMalformedConfigurations() {
        assertThrows(IllegalArgumentException.class, () -> Threshold.of(0.0, 0.5, 0.9));
        assertThrows(IllegalArgumentException.class, () -> Threshold.of(1000.0, 0.9, 0.5));
        assertThrows(IllegalArgumentException.class, () -> Threshold.of(1000.0, -0.1, 0.9));
        assertThrows(IllegalArgumentException.class, () -> Threshold.of(1000.0, 0.5, 1.5));
        assertThrows(IllegalArgumentException.class, () -> Threshold.of(Double.NaN, 0.5, 0.9));
    }

    @Test
    void severityFromRawValue() {
        Threshold t = Threshold.standard(1000.0);
        assertEquals(Severity.WARN, t.severityOfValue(700.0));
        assertEquals(Severity.ALERT, t.severityOfValue(900.0));
    }
}
'''

FILES[f"{T}/com/cistern/model/CsvCodecTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CsvCodecTest {

    @Test
    void parsesPipelineFormat() {
        String csv = ""
                + "# sample capture from site north-01\\n"
                + "\\n"
                + "1000,250,litres,probe-a\\n"
                + "2000,30,gal-uk,probe-b\\n"
                + "3000,1,m3,\\n";
        List<Sample> samples = CsvCodec.parseSamples(csv);
        assertEquals(3, samples.size());
        assertEquals(250.0, samples.get(0).value(), 1e-9);
        assertEquals(30.0 * 4.54609, samples.get(1).valueLitres(), 1e-9);
        assertEquals(1000.0, samples.get(2).valueLitres(), 1e-9);
    }

    @Test
    void roundTripsThroughSerialisation() {
        List<Sample> original = List.of(
                Sample.of(1L, 2.0, Units.LITRES, "a"),
                Sample.of(2L, 3.5, Units.GALLONS_US, "b"));
        List<Sample> reparsed = CsvCodec.parseSamples(CsvCodec.writeSamples(original));
        assertEquals(original, reparsed);
    }

    @Test
    void rejectsMalformedRows() {
        assertThrows(IllegalArgumentException.class, () -> CsvCodec.parseSamples("abc"));
        assertThrows(IllegalArgumentException.class, () -> CsvCodec.parseSamples("1,x,l"));
        assertThrows(IllegalArgumentException.class, () -> CsvCodec.parseSamples("1,2,bogus"));
        assertThrows(IllegalArgumentException.class, () -> CsvCodec.parseSamples("nope,2,l"));
    }

    @Test
    void emptyDocumentYieldsNoSamples() {
        assertTrue(CsvCodec.parseSamples("").isEmpty());
        assertTrue(CsvCodec.parseSamples("# only comments\\n\\n").isEmpty());
    }
}
'''

FILES[f"{T}/com/cistern/model/LevelMathTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LevelMathTest {

    @Test
    void clamp01Saturates() {
        assertEquals(1.0, LevelMath.clamp01(1.5), 1e-9);
        assertEquals(0.0, LevelMath.clamp01(-1.0), 1e-9);
        assertEquals(0.5, LevelMath.clamp01(0.5), 1e-9);
    }

    @Test
    void nanDegradesToLowerBound() {
        assertEquals(0.0, LevelMath.clamp01(Double.NaN), 1e-9);
        assertEquals(-1.0, LevelMath.clamp(-1.0, 1.0, Double.NaN), 1e-9);
    }

    @Test
    void nearZeroTolerance() {
        assertTrue(LevelMath.nearZero(0.0, 1e-9));
        assertTrue(LevelMath.nearZero(5e-10, 1e-9));
        assertFalse(LevelMath.nearZero(0.5, 1e-9));
    }
}
'''

T = "cistern-core/src/test/java"
FILES[f"{T}/com/cistern/core/BaselineAssessorTest.java"] = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Baseline strategy coverage: pins the arithmetic-mean estimator and the
 * level clamp against the standard 1000-litre threshold.
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
    void meanOfEvenWindowIsTheAverage() {
        // mean of {1, 2, 3, 100} is 26.5 of capacity 1000 -> level 0.0265
        assertEquals(0.0265, assessor.assess(window(1.0, 2.0, 3.0, 100.0), THRESHOLD), 1e-9);
    }

    @Test
    void meanOfOddWindowIsTheAverage() {
        // mean of {10, 35, 45} is 30.0 of capacity 1000 -> level 0.03
        assertEquals(0.03, assessor.assess(window(10.0, 35.0, 45.0), THRESHOLD), 1e-9);
    }

    @Test
    void singleSampleLevelIsItsShareOfCapacity() {
        assertEquals(0.25, assessor.assess(window(250.0), THRESHOLD), 1e-9);
    }

    @Test
    void meanOfMixedUnitsNormalisesToLitres() {
        SampleWindow mixed = SampleWindow.of(
                Sample.litres(1L, 400.0),
                Sample.of(2L, 400.0, com.cistern.model.Units.MILLILITRES, "probe"),
                Sample.litres(3L, 400.0));
        // mean is (400 + 0.4 + 400) / 3 = 266.8 litres -> 0.2668
        assertEquals(0.2668, assessor.assess(mixed, THRESHOLD), 1e-9);
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
        assertTrue(assessor.describe().contains("mean"));
    }
}
'''

FILES[f"{T}/com/cistern/core/PeakAssessorTest.java"] = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PeakAssessorTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final PeakAssessor assessor = new PeakAssessor();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void reportsMaximumAsLevel() {
        assertEquals(0.8, assessor.assess(window(100.0, 800.0, 400.0), THRESHOLD), 1e-9);
    }

    @Test
    void emptyWindowIsZero() {
        assertEquals(0.0, assessor.assess(SampleWindow.of(), THRESHOLD), 1e-9);
    }

    @Test
    void clampsAboveCapacity() {
        assertEquals(1.0, assessor.assess(window(500.0, 1300.0), THRESHOLD), 1e-9);
    }

    @Test
    void exposesStableCodeAndDescription() {
        assertEquals("peak", assessor.code());
        assertTrue(assessor.describe().contains("maximum"));
    }
}
'''

FILES[f"{T}/com/cistern/core/SurgeAssessorTest.java"] = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class SurgeAssessorTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final SurgeAssessor assessor = new SurgeAssessor();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void detectsLateActivity() {
        // recent quarter mean 500 vs whole mean 300 against capacity 1000
        assertEquals(0.2, assessor.assess(
                window(100.0, 100.0, 100.0, 500.0, 500.0, 500.0), THRESHOLD), 1e-9);
    }

    @Test
    void flatWindowHasNoSurge() {
        assertEquals(0.0, assessor.assess(window(100.0, 100.0, 100.0), THRESHOLD), 1e-9);
    }

    @Test
    void emptyWindowIsZero() {
        assertEquals(0.0, assessor.assess(SampleWindow.of(), THRESHOLD), 1e-9);
    }
}
'''

FILES[f"{T}/com/cistern/core/AssessorRegistryTest.java"] = '''package com.cistern.core;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AssessorRegistryTest {

    @Test
    void resolvesKnownCodes() {
        assertTrue(AssessorRegistry.byCode("baseline") instanceof BaselineAssessor);
        assertTrue(AssessorRegistry.byCode("peak") instanceof PeakAssessor);
        assertTrue(AssessorRegistry.byCode("surge") instanceof SurgeAssessor);
    }

    @Test
    void unknownCodesFallBackToBaseline() {
        assertTrue(AssessorRegistry.byCode("bogus") instanceof BaselineAssessor);
        assertTrue(AssessorRegistry.byCode(null) instanceof BaselineAssessor);
    }

    @Test
    void listsAllCodes() {
        assertEquals(6, AssessorRegistry.codes().size());
        assertTrue(AssessorRegistry.codes().contains("baseline"));
        assertTrue(AssessorRegistry.codes().contains("drift"));
        assertTrue(AssessorRegistry.codes().contains("stability"));
        assertTrue(AssessorRegistry.contains("trough"));
        assertTrue(AssessorRegistry.contains("baseline"));
    }
}
'''

FILES[f"{T}/com/cistern/core/AssessmentEngineTest.java"] = '''package com.cistern.core;

import com.cistern.model.Assessment;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class AssessmentEngineTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final AssessmentEngine engine = new AssessmentEngine();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void evaluateWrapsStrategyOutput() {
        SampleWindow w = window(100.0, 200.0, 300.0);
        Assessment assessment = engine.evaluate(w, THRESHOLD, "baseline");
        assertEquals("baseline", assessment.code());
        BaselineAssessor direct = new BaselineAssessor();
        assertEquals(direct.assess(w, THRESHOLD), assessment.level(), 1e-9);
        assertFalse(assessment.method().isBlank());
    }

    @Test
    void severityIsDecoratedFromTheLevel() {
        Assessment assessment = engine.evaluate(window(600.0, 700.0), THRESHOLD, "baseline");
        assertEquals("warn", assessment.severity().code());
    }

    @Test
    void peakCodeGivesPeakLevel() {
        Assessment assessment = engine.evaluate(window(100.0, 300.0), THRESHOLD, "peak");
        assertEquals(0.3, assessment.level(), 1e-9);
        assertEquals("nominal", assessment.severity().code());
    }
}
'''

T = "cistern-report/src/test/java"
FILES[f"{T}/com/cistern/report/ReportFormatTest.java"] = '''package com.cistern.report;

import com.cistern.core.BaselineAssessor;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Report structure and key-name contract. These assertions describe the
 * output format and must hold for every strategy, including the baseline.
 */
class ReportFormatTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private final ReportPipeline pipeline = new ReportPipeline();

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void rootKeysAreStable() {
        Map<String, Object> report = pipeline.renderMap("peak", window(100.0, 300.0, 200.0), THRESHOLD);
        assertEquals(Set.of("header", "window", "measures", "trend"), report.keySet());
    }

    @Test
    void headerFieldsArePresent() {
        Map<String, Object> report = pipeline.renderMap("peak", window(100.0, 300.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> header = (Map<String, Object>) report.get("header");
        assertEquals("pipeline", header.get("station"));
        assertEquals("cistern-report/1.4.2", header.get("generator"));
        assertTrue(((String) header.get("report_id")).length() >= 8);
    }

    @Test
    void peakMeasureSurfacesThroughThePipeline() {
        Map<String, Object> report = pipeline.renderMap("peak", window(100.0, 300.0, 200.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> measures = (Map<String, Object>) report.get("measures");
        @SuppressWarnings("unchecked")
        Map<String, Object> peak = (Map<String, Object>) measures.get("peak");
        assertEquals(0.3, ((Number) peak.get("level")).doubleValue(), 1e-9);
        assertEquals("nominal", peak.get("severity"));
        assertTrue(((String) peak.get("method")).contains("maximum"));
    }

    @Test
    void baselineLevelMatchesTheAssessorDirectly() {
        SampleWindow w = window(100.0, 900.0, 200.0, 800.0);
        Map<String, Object> report = pipeline.renderMap("baseline", w, THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> measures = (Map<String, Object>) report.get("measures");
        @SuppressWarnings("unchecked")
        Map<String, Object> baseline = (Map<String, Object>) measures.get("baseline");
        double expected = new BaselineAssessor().assess(w, THRESHOLD);
        assertEquals(expected, ((Number) baseline.get("level")).doubleValue(), 1e-9);
    }

    @Test
    void windowBlockReportsSampleCount() {
        Map<String, Object> report = pipeline.renderMap("baseline", window(1.0, 2.0, 3.0), THRESHOLD);
        @SuppressWarnings("unchecked")
        Map<String, Object> windowBlock = (Map<String, Object>) report.get("window");
        assertEquals(3, ((Number) windowBlock.get("samples")).intValue());
    }
}
'''

FILES[f"{T}/com/cistern/report/TextReportRendererTest.java"] = '''package com.cistern.report;

import com.cistern.core.AssessorRegistry;
import com.cistern.model.ReportHeader;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class TextReportRendererTest {

    private final TextReportRenderer renderer = new TextReportRenderer();

    @Test
    void rendersAllStrategyRows() {
        Sample[] samples = {
                Sample.litres(1L, 100.0),
                Sample.litres(2L, 200.0),
                Sample.litres(3L, 150.0)};
        SampleWindow window = SampleWindow.of(samples);
        Report report = new ReportBuilder().buildAll(
                ReportHeader.now("site-9"), window, Threshold.standard(1000.0));
        String text = renderer.render(report);
        assertTrue(text.contains("Cistern level report"));
        assertTrue(text.contains("station: site-9"));
        for (String code : AssessorRegistry.codes()) {
            assertTrue(text.contains(code), "missing row for " + code);
        }
        assertTrue(text.contains("trend"));
    }
}
'''

FILES[f"{T}/com/cistern/report/LabelTableTest.java"] = '''package com.cistern.report;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class LabelTableTest {

    @Test
    void labelsRegisteredStrategies() {
        assertEquals("Baseline level", LabelTable.label("baseline"));
        assertEquals("Surge margin", LabelTable.label("surge"));
    }

    @Test
    void unknownCodesPassThrough() {
        assertEquals("bogus", LabelTable.label("bogus"));
    }

    @Test
    void allReturnsSixLabels() {
        assertEquals(6, LabelTable.all().size());
    }
}
'''

FILES[f"{T}/com/cistern/report/JsonReportRendererTest.java"] = '''package com.cistern.report;

import com.cistern.model.ReportHeader;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JsonReportRendererTest {

    private final JsonReportRenderer renderer = new JsonReportRenderer();

    private static Report singleBaselineReport() {
        return new ReportBuilder().buildSingle(
                ReportHeader.now("site-2"),
                SampleWindow.of(Sample.litres(1L, 100.0), Sample.litres(2L, 200.0)),
                Threshold.standard(1000.0), "baseline");
    }

    @Test
    void rendersSingleBaselineReportJson() {
        String json = renderer.render(singleBaselineReport());
        assertTrue(json.startsWith("{"));
        assertTrue(json.endsWith("}"));
        assertTrue(json.contains("\\"baseline\\""));
        assertTrue(json.contains("\\"level\\""));
        assertTrue(json.contains("\\"severity\\""));
        assertTrue(json.contains("\\"method\\""));
        assertTrue(json.contains("\\"nominal\\""));
    }

    @Test
    void outputIsDeterministic() {
        Report report = singleBaselineReport();
        assertEquals(renderer.render(report), renderer.render(report));
    }
}
'''

T = "cistern-cli/src/test/java"
FILES[f"{T}/com/cistern/cli/MainTest.java"] = '''package com.cistern.cli;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MainTest {

    private static String capture(Runnable runnable) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        PrintStream original = System.out;
        System.setOut(new PrintStream(buffer));
        try {
            runnable.run();
        } finally {
            System.setOut(original);
        }
        return buffer.toString();
    }

    @Test
    void versionCommandWorks() {
        assertEquals(0, Main.run(new String[]{"version"}));
        assertTrue(capture(() -> Main.run(new String[]{"version"})).contains("cistern-cli"));
    }

    @Test
    void convertGallonsToLitres() {
        assertEquals(0, Main.run(new String[]{"convert", "1", "l", "gal-uk"}));
        String out = capture(() -> Main.run(new String[]{"convert", "1", "l", "gal-uk"}));
        assertTrue(out.contains("0.219969"), "unexpected conversion output: " + out);
    }

    @Test
    void assessPeakFromCsv() throws Exception {
        Path csv = Files.createTempFile("cistern-", ".csv");
        Files.writeString(csv, "# window\\n1000,100,l,probe\\n2000,800,l,probe\\n3000,400,l,probe\\n");
        try {
            assertEquals(0, Main.run(new String[]{"assess", "peak", "1000", csv.toString()}));
            String out = capture(() -> Main.run(new String[]{"assess", "peak", "1000", csv.toString()}));
            assertTrue(out.startsWith("peak 0.8 warn"), "unexpected assess output: " + out);
        } finally {
            Files.deleteIfExists(csv);
        }
    }

    @Test
    void historyListsSeverityPerRow() throws Exception {
        Path csv = Files.createTempFile("cistern-h-", ".csv");
        Files.writeString(csv, "1000,500,l,probe\\n2000,900,l,probe\\n");
        try {
            String out = capture(() -> Main.run(new String[]{"history", "1000", csv.toString()}));
            assertTrue(out.contains("0.5 nominal"), "unexpected history output: " + out);
            assertTrue(out.contains("0.9 alert"), "unexpected history output: " + out);
        } finally {
            Files.deleteIfExists(csv);
        }
    }

    @Test
    void unknownCommandIsUsageError() {
        assertEquals(2, Main.run(new String[]{"frobnicate"}));
    }

    @Test
    void noArgumentsPrintsUsage() {
        assertEquals(0, Main.run(new String[]{}));
        assertTrue(capture(() -> Main.run(new String[]{})).contains("usage: cistern"));
    }
}
'''
T = "cistern-model/src/test/java"
FILES[f"{T}/com/cistern/model/TimeShifterTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class TimeShifterTest {

    @Test
    void shiftMovesEveryTimestamp() {
        SampleWindow shifted = TimeShifter.shift(
                SampleWindow.of(Sample.litres(1000L, 1.0), Sample.litres(2000L, 2.0)), 5000L);
        assertEquals(6000L, shifted.samples().get(0).timestampMillis());
        assertEquals(7000L, shifted.samples().get(1).timestampMillis());
        assertEquals(1.0, shifted.samples().get(0).value(), 1e-9);
    }

    @Test
    void alignFloorsToInterval() {
        SampleWindow aligned = TimeShifter.alignTo(
                SampleWindow.of(Sample.litres(1003L, 1.0), Sample.litres(2999L, 2.0)), 1000L);
        assertEquals(1000L, aligned.samples().get(0).timestampMillis());
        assertEquals(2000L, aligned.samples().get(1).timestampMillis());
    }

    @Test
    void alignRejectsNonPositiveIntervals() {
        assertThrows(IllegalArgumentException.class,
                () -> TimeShifter.alignTo(SampleWindow.of(), 0L));
    }
}
'''

FILES[f"{T}/com/cistern/model/OutageCalendarTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OutageCalendarTest {

    @Test
    void intervalsAreHalfOpen() {
        OutageCalendar calendar = new OutageCalendar().add(100L, 200L);
        assertTrue(calendar.contains(100L));
        assertTrue(calendar.contains(199L));
        assertFalse(calendar.contains(200L));
        assertFalse(calendar.contains(99L));
    }

    @Test
    void overlapsDetectsAnyTouch() {
        OutageCalendar calendar = new OutageCalendar().add(100L, 200L);
        assertTrue(calendar.overlaps(150L, 250L));
        assertTrue(calendar.overlaps(90L, 110L));
        assertFalse(calendar.overlaps(300L, 400L));
        assertFalse(calendar.overlaps(200L, 250L));
    }

    @Test
    void coverageIsFractionOfWindow() {
        OutageCalendar calendar = new OutageCalendar().add(1L, 3L).add(5L, 6L);
        SampleWindow window = SampleWindow.of(
                Sample.litres(1L, 1.0),
                Sample.litres(2L, 2.0),
                Sample.litres(3L, 3.0),
                Sample.litres(4L, 4.0));
        assertEquals(2, calendar.coveredSamples(window));
        assertEquals(0.5, calendar.coverage(window), 1e-9);
    }

    @Test
    void rejectsInvertedInterval() {
        org.junit.jupiter.api.Assertions.assertThrows(IllegalArgumentException.class,
                () -> new OutageCalendar().add(200L, 100L));
    }
}
'''

FILES[f"{T}/com/cistern/model/WindowMergerTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class WindowMergerTest {

    @Test
    void mergesChronologicallyDeduplicatingTimestamps() {
        SampleWindow first = SampleWindow.of(
                Sample.litres(1L, 10.0),
                Sample.litres(2L, 20.0));
        SampleWindow second = SampleWindow.of(
                Sample.litres(2L, 999.0),
                Sample.litres(3L, 30.0));
        SampleWindow merged = WindowMerger.merge(first, second);
        assertEquals(3, merged.size());
        assertEquals(10.0, merged.samples().get(0).value(), 1e-9);
        assertEquals(20.0, merged.samples().get(1).value(), 1e-9);
        assertEquals(30.0, merged.samples().get(2).value(), 1e-9);
    }

    @Test
    void distinctCountMatchesMergedSize() {
        SampleWindow first = SampleWindow.of(Sample.litres(5L, 1.0));
        SampleWindow second = SampleWindow.of(Sample.litres(6L, 2.0));
        assertEquals(2, WindowMerger.distinctCount(first, second));
        assertEquals(1, WindowMerger.distinctCount(first, first));
    }
}
'''

T = "cistern-core/src/test/java"
FILES[f"{T}/com/cistern/core/CalibrationTest.java"] = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CalibrationTest {

    private static final double CAPACITY = 1000.0;
    private static final Calibration CALIBRATION = new Calibration(CAPACITY);

    private static long millis(int year, int month, int day, int hour) {
        return ZonedDateTime.of(year, month, day, hour, 0, 0, 0, ZoneOffset.UTC)
                .toInstant().toEpochMilli();
    }

    @Test
    void perfectFitHasZeroResidual() {
        // June, hour 3: expected = 0.7 * 0.92 = 0.644 of capacity
        long timestamp = millis(2025, 6, 1, 3);
        SampleWindow window = SampleWindow.of(Sample.litres(timestamp, 0.644 * CAPACITY));
        assertEquals(0.0, CALIBRATION.meanResidual(window), 1e-9);
    }

    @Test
    void offFitShowsResidual() {
        long timestamp = millis(2025, 6, 1, 3);
        SampleWindow window = SampleWindow.of(Sample.litres(timestamp, 0.05 * CAPACITY));
        assertTrue(CALIBRATION.meanResidual(window) > 0.4);
    }

    @Test
    void emptyWindowIsZero() {
        assertEquals(0.0, CALIBRATION.meanResidual(SampleWindow.of()), 1e-9);
        assertEquals(0L, CALIBRATION.inSpecSamples(SampleWindow.of(), 0.05));
    }

    @Test
    void inSpecCountsSamplesNearExpectation() {
        long timestamp = millis(2025, 1, 15, 23);
        // January hour 23: expected = 0.9 * 1.10 = 0.99 of capacity
        SampleWindow window = SampleWindow.of(
                Sample.litres(timestamp, 0.99 * CAPACITY),
                Sample.litres(timestamp + 1L, 0.10 * CAPACITY));
        assertEquals(1L, CALIBRATION.inSpecSamples(window, 0.01));
    }

    @Test
    void rejectsBadCapacity() {
        assertThrows(IllegalArgumentException.class, () -> new Calibration(0.0));
    }
}
'''

FILES[f"{T}/com/cistern/core/ConfidenceBandTest.java"] = '''package com.cistern.core;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ConfidenceBandTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private static SampleWindow window(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return SampleWindow.of(samples);
    }

    @Test
    void singleSampleBandIsPoint() {
        ConfidenceBand band = ConfidenceBand.of(new PeakAssessor(), window(500.0), THRESHOLD);
        assertEquals(0.5, band.center(), 1e-9);
        assertEquals(0.0, band.halfWidth(), 1e-9);
    }

    @Test
    void bandContainsCenter() {
        ConfidenceBand band = ConfidenceBand.of(new BaselineAssessor(),
                window(100.0, 200.0, 900.0), THRESHOLD);
        assertTrue(band.lower() <= band.center() + 1e-12);
        assertTrue(band.center() - 1e-12 <= band.upper());
    }

    @Test
    void lowerSaturatesAtZero() {
        double[] values = new double[50];
        java.util.Arrays.fill(values, 1.0);
        values[0] = 1000.0;
        ConfidenceBand band = ConfidenceBand.of(new BaselineAssessor(),
                window(values), THRESHOLD);
        assertEquals(0.0, band.lower(), 1e-9);
    }
}
'''

T = "cistern-report/src/test/java"
FILES[f"{T}/com/cistern/report/SparklinesTest.java"] = '''package com.cistern.report;

import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class SparklinesTest {

    @Test
    void levelBarRendersFixedWidth() {
        assertEquals("**********", Sparklines.levelBar(1.0, 10));
        assertEquals("........", Sparklines.levelBar(0.0, 8));
        assertEquals("*****.....", Sparklines.levelBar(0.5, 10));
        assertEquals("", Sparklines.levelBar(0.5, 0));
    }

    @Test
    void flatWindowDrawsFullSparkline() {
        assertEquals("****", Sparklines.sparkline(
                SampleWindow.of(Sample.litres(1L, 5.0), Sample.litres(2L, 5.0)), 4));
    }

    @Test
    void emptyWindowDrawsBlanks() {
        assertEquals("   ", Sparklines.sparkline(SampleWindow.of(), 3));
        assertEquals("", Sparklines.sparkline(SampleWindow.of(), 0));
    }

    @Test
    void risingWindowTouchesAllGlyphs() {
        SampleWindow w = SampleWindow.of(
                Sample.litres(1L, 0.0),
                Sample.litres(2L, 1.0),
                Sample.litres(3L, 2.0),
                Sample.litres(4L, 3.0),
                Sample.litres(5L, 4.0));
        String spark = Sparklines.sparkline(w, 5);
        assertEquals(5, spark.length());
        // first column is the low bucket, last column the high bucket
        assertEquals(' ', spark.charAt(0));
        assertEquals('*', spark.charAt(spark.length() - 1));
    }
}
'''

T = "cistern-cli/src/test/java"
FILES[f"{T}/com/cistern/cli/TableTest.java"] = '''package com.cistern.cli;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TableTest {

    @Test
    void alignsColumns() {
        Table table = Table.withColumns("code", "estimator");
        table.addRow(List.of("baseline", "median"));
        table.addRow(List.of("peak", "maximum"));
        String rendered = table.render();
        assertTrue(rendered.startsWith("code      estimator"), rendered);
        assertTrue(rendered.contains("baseline  median"), rendered);
        assertTrue(rendered.contains("peak      maximum"), rendered);
    }

    @Test
    void mismatchedRowIsRejected() {
        Table table = Table.withColumns("a", "b");
        assertThrows(IllegalArgumentException.class, () -> table.addRow(List.of("x")));
    }
}
'''

FILES[f"{T}/com/cistern/cli/InspectCommandTest.java"] = '''package com.cistern.cli;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InspectCommandTest {

    private static String capture(Runnable runnable) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        PrintStream original = System.out;
        System.setOut(new PrintStream(buffer));
        try {
            runnable.run();
        } finally {
            System.setOut(original);
        }
        return buffer.toString();
    }

    @Test
    void inspectListsStrategiesAndCalibration() {
        assertEquals(0, Main.run(new String[]{"inspect"}));
        String out = capture(() -> Main.run(new String[]{"inspect"}));
        assertTrue(out.contains("registered strategies:"));
        assertTrue(out.contains("baseline"));
        assertTrue(out.contains("surge"));
        assertTrue(out.contains("hourly fill fraction:"));
    }
}
'''

FILES[f"{T}/com/cistern/cli/CompareCommandTest.java"] = '''package com.cistern.cli;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CompareCommandTest {

    private static String capture(Runnable runnable) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        PrintStream original = System.out;
        System.setOut(new PrintStream(buffer));
        try {
            runnable.run();
        } finally {
            System.setOut(original);
        }
        return buffer.toString();
    }

    @Test
    void comparesWindowsAndMerges() throws Exception {
        Path before = Files.createTempFile("cistern-b-", ".csv");
        Path after = Files.createTempFile("cistern-a-", ".csv");
        Files.writeString(before, "1000,200,l,probe\\n2000,300,l,probe\\n");
        Files.writeString(after, "3000,400,l,probe\\n4000,500,l,probe\\n");
        try {
            assertEquals(0, Main.run(new String[]{"compare", "1000", before.toString(), after.toString()}));
            String out = capture(() -> Main.run(new String[]{"compare", "1000", before.toString(), after.toString()}));
            assertTrue(out.contains("baseline"));
            assertTrue(out.contains("merged window: 4 samples (4 input)"), out);
        } finally {
            Files.deleteIfExists(before);
            Files.deleteIfExists(after);
        }
    }
}
'''

T = "cistern-model/src/test/java"
FILES[f"{T}/com/cistern/model/DurationFormatTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class DurationFormatTest {

    @Test
    void formatsSecondsMinutesHours() {
        assertEquals("45s", DurationFormat.format(45_000L));
        assertEquals("3m 12s", DurationFormat.format(192_000L));
        assertEquals("3h 4m", DurationFormat.format(11_040_000L));
        assertEquals("0s", DurationFormat.format(0L));
    }

    @Test
    void formatsSecondsHelper() {
        assertEquals("3h 4m", DurationFormat.formatSeconds(11_040L));
    }
}
'''

FILES[f"{T}/com/cistern/model/JsonCodecTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class JsonCodecTest {

    private static final char BS = (char) 92; // backslash
    private static final char QU = (char) 34; // double quote

    @Test
    void escapesQuotesAndBackslashesInsideValues() {
        String value = "a" + BS + QU + "b"; // a \ " b
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("k", value);
        String expected = "{" + QU + "k" + QU + ":" + QU + "a" + BS + BS + BS + QU + "b" + QU + "}";
        assertEquals(expected, JsonCodec.writeObject(root));
    }

    @Test
    void escapesControlCharacters() {
        String newline = "a" + (char) 10 + "b"; // a <LF> b
        assertEquals("a" + BS + "nb", JsonCodec.escape(newline));
        String control = "" + (char) 1;
        assertEquals(BS + "u0001", JsonCodec.escape(control));
        assertEquals("plain", JsonCodec.escape("plain"));
    }

    @Test
    void writesNestedStructures() {
        Map<String, Object> inner = new LinkedHashMap<>();
        inner.put("level", 0.25);
        inner.put("severity", "nominal");
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("measures", inner);
        root.put("tags", List.of("a", "b"));
        root.put("ok", true);
        root.put("nothing", null);
        String expected = "{" + QU + "measures" + QU + ":{" + QU + "level" + QU + ":0.25,"
                + QU + "severity" + QU + ":" + QU + "nominal" + QU + "},"
                + QU + "tags" + QU + ":[" + QU + "a" + QU + "," + QU + "b" + QU + "],"
                + QU + "ok" + QU + ":true,"
                + QU + "nothing" + QU + ":null}";
        assertEquals(expected, JsonCodec.writeObject(root));
    }

    @Test
    void formatsNumbersDeterministically() {
        assertEquals("0", JsonCodec.formatNumber(0.0));
        assertEquals("26.5", JsonCodec.formatNumber(26.5));
        assertEquals("0.0025", JsonCodec.formatNumber(0.0025));
        assertEquals("1", JsonCodec.formatNumber(1.0));
    }

    @Test
    void rejectsUnsupportedValueTypes() {
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("bad", new Object());
        assertThrows(IllegalArgumentException.class, () -> JsonCodec.writeObject(root));
    }
}
'''

T = "cistern-core/src/test/java"
FILES[f"{T}/com/cistern/core/AssessmentValidatorTest.java"] = '''package com.cistern.core;

import com.cistern.model.Assessment;
import com.cistern.model.Severity;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AssessmentValidatorTest {

    @Test
    void validAssessmentHasNoProblems() {
        Assessment good = Assessment.of("baseline", "estimator", 0.5, Severity.WARN);
        assertTrue(AssessmentValidator.problems(good).isEmpty());
    }

    @Test
    void flagsOutOfBandLevels() {
        Assessment wild = Assessment.of("peak", "estimator", 1.5, Severity.ALERT);
        assertFalse(AssessmentValidator.problems(wild).isEmpty());
    }

    @Test
    void flagsBlankCodeAndNonFiniteLevel() {
        assertFalse(AssessmentValidator.problems(
                Assessment.of(" ", "method", 0.5, Severity.NOMINAL)).isEmpty());
        assertFalse(AssessmentValidator.problems(
                Assessment.of("x", "method", Double.NaN, Severity.NOMINAL)).isEmpty());
    }

    @Test
    void requireValidThrowsOnViolation() {
        assertThrows(IllegalStateException.class,
                () -> AssessmentValidator.requireValid(List.of(
                        Assessment.of("x", "method", -0.5, Severity.NOMINAL))));
    }

    @Test
    void severityForLevelMatchesBands() {
        assertEquals(Severity.NOMINAL, AssessmentValidator.severityForLevel(0.5));
        assertEquals(Severity.WARN, AssessmentValidator.severityForLevel(0.7));
        assertEquals(Severity.ALERT, AssessmentValidator.severityForLevel(0.9));
        assertEquals(Severity.CRITICAL, AssessmentValidator.severityForLevel(1.0));
    }
}
'''

T = "cistern-model/src/test/java"
FILES[f"{T}/com/cistern/model/SummaryTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SummaryTest {

    @Test
    void freezesHeadlineStats() {
        SampleWindow window = SampleWindow.of(
                Sample.litres(1L, 2.0),
                Sample.litres(2L, 4.0),
                Sample.litres(3L, 4.0),
                Sample.litres(4L, 4.0),
                Sample.litres(5L, 5.0),
                Sample.litres(6L, 5.0),
                Sample.litres(7L, 7.0),
                Sample.litres(8L, 9.0));
        Summary summary = Summary.of(window);
        assertEquals(8, summary.count());
        assertEquals(2.0, summary.min(), 1e-9);
        assertEquals(9.0, summary.max(), 1e-9);
        assertEquals(5.0, summary.mean(), 1e-9);
        assertEquals(2.0, summary.standardDeviation(), 1e-9);
        assertEquals(7.0, summary.range(), 1e-9);
    }

    @Test
    void emptyWindowSummary() {
        Summary summary = Summary.of(SampleWindow.of());
        assertTrue(summary.isEmpty());
        assertEquals(0, summary.count());
        assertEquals(6, summary.toMap().size());
    }
}
'''

FILES[f"{T}/com/cistern/model/TrendTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TrendTest {

    @Test
    void classifiesDeltas() {
        assertEquals(Trend.RISING, Trend.fromDelta(0.05, 0.01));
        assertEquals(Trend.FALLING, Trend.fromDelta(-0.05, 0.01));
        assertEquals(Trend.FLAT, Trend.fromDelta(0.005, 0.01));
    }

    @Test
    void betweenComparesLevels() {
        assertEquals(Trend.RISING, Trend.between(0.2, 0.5));
        assertEquals(Trend.FALLING, Trend.between(0.5, 0.2));
        assertEquals(Trend.FLAT, Trend.between(0.2, 0.21));
    }
}
'''

FILES[f"{T}/com/cistern/model/ReportHeaderTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ReportHeaderTest {

    @Test
    void nowBuildsRandomHeader() {
        ReportHeader header = ReportHeader.now("site-1");
        assertEquals("site-1", header.stationId());
        assertTrue(header.reportId().length() >= 8);
        assertTrue(header.generatedAtMillis() > 0L);
    }

    @Test
    void rejectsBlankStation() {
        assertThrows(IllegalArgumentException.class, () -> new ReportHeader("  ", "id", 0L));
    }

    @Test
    void generatorBannerIsStable() {
        assertEquals("cistern-report/1.4.2", ReportHeader.GENERATOR);
    }
}
'''

FILES[f"{T}/com/cistern/model/TankSpecTest.java"] = '''package com.cistern.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class TankSpecTest {

    @Test
    void derivesThresholdFromFractions() {
        TankSpec spec = new TankSpec("north-01", 5000.0, 0.5, 0.8, Units.GALLONS_UK);
        Threshold threshold = spec.toThreshold();
        assertEquals(5000.0, threshold.capacity(), 1e-9);
        assertEquals(0.5, threshold.warnFraction(), 1e-9);
        assertEquals(0.8, threshold.alertFraction(), 1e-9);
    }

    @Test
    void formatsInDisplayUnit() {
        TankSpec spec = TankSpec.standard("north-01", 5000.0);
        assertEquals("2500.0 gal-uk",
                new TankSpec("north-01", 5000.0, 0.6, 0.85, Units.GALLONS_UK)
                        .formatLitres(2500.0 * 4.54609));
    }

    @Test
    void rejectsBadSpecs() {
        assertThrows(IllegalArgumentException.class,
                () -> new TankSpec("", 5000.0, 0.6, 0.85, Units.LITRES));
        assertThrows(IllegalArgumentException.class,
                () -> new TankSpec("north-01", 0.0, 0.6, 0.85, Units.LITRES));
    }
}
'''

T = "cistern-core/src/test/java"
FILES[f"{T}/com/cistern/core/AssessmentHistoryTest.java"] = '''package com.cistern.core;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AssessmentHistoryTest {

    @Test
    void retainsOnlyNewestEntries() {
        AssessmentHistory history = new AssessmentHistory(2);
        history.record("baseline", 0.1)
               .record("peak", 0.2)
               .record("drift", 0.3);
        assertEquals(2, history.size());
        assertEquals(0.2, history.entries().get(0).level(), 1e-9);
        assertEquals("peak", history.entries().get(0).code());
        assertEquals("drift", history.last().orElseThrow().code());
    }

    @Test
    void summaryIsChronological() {
        AssessmentHistory history = new AssessmentHistory(4);
        history.record("baseline", 0.25).record("peak", 1.0);
        assertEquals("baseline=0.25, peak=1", history.summary());
    }

    @Test
    void rejectsBadCapacityAndCodes() {
        assertThrows(IllegalArgumentException.class, () -> new AssessmentHistory(0));
        assertThrows(IllegalArgumentException.class,
                () -> new AssessmentHistory(2).record("  ", 0.5));
    }

    @Test
    void containsCodeWorks() {
        AssessmentHistory history = new AssessmentHistory(3).record("peak", 0.5);
        assertTrue(history.containsCode("peak"));
        assertTrue(!history.containsCode("baseline"));
    }
}
'''

T = "cistern-report/src/test/java"
FILES[f"{T}/com/cistern/report/ReportComparatorTest.java"] = '''package com.cistern.report;

import com.cistern.model.ReportHeader;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ReportComparatorTest {

    private static final Threshold THRESHOLD = Threshold.standard(1000.0);

    private static Report single(double... values) {
        Sample[] samples = new Sample[values.length];
        for (int i = 0; i < values.length; i++) {
            samples[i] = Sample.litres(i * 1000L, values[i]);
        }
        return new ReportBuilder().buildSingle(
                ReportHeader.now("cmp"), SampleWindow.of(samples), THRESHOLD, "baseline");
    }

    @Test
    void deltasAreAfterMinusBefore() {
        Report before = single(100.0, 300.0);
        Report after = single(300.0, 400.0);
        double peakDelta = ReportComparator.levelDeltas(before, after).get("baseline");
        assertEquals(after.measure("baseline").orElseThrow().level()
                        - before.measure("baseline").orElseThrow().level(),
                peakDelta, 1e-9);
    }

    @Test
    void identicalReportsAreUnchanged() {
        Report first = single(100.0, 300.0);
        assertTrue(ReportComparator.levelsUnchanged(first, single(100.0, 300.0)));
        assertFalse(ReportComparator.levelsUnchanged(first, single(100.0, 400.0)));
    }

    @Test
    void describeIsReadable() {
        String description = ReportComparator.describe(single(100.0), single(200.0));
        assertTrue(description.contains("baseline="), description);
    }
}
'''
