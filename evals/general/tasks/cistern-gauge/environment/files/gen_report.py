# -*- coding: utf-8 -*-
"""Sources for the cistern-report module (com.cistern.report).

Part of the cistern-gauge fixture generator. The report module depends on the
cistern-core strategies exclusively through the LevelAssessor interface.
"""

SRC = "cistern-report/src/main/java"

FILES = {}

FILES[f"{SRC}/com/cistern/report/Report.java"] = '''package com.cistern.report;

import com.cistern.model.Assessment;
import com.cistern.model.ReportHeader;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Structured report: a header, the assessed window and one assessed level per
 * measure code.
 *
 * <p>{@link ReportBuilder} assembles reports and the renderers turn them into
 * text or JSON. The key names in {@link #toMap()} are part of the output
 * contract: consumers - including graders - match on them, so they must not
 * be renamed casually.
 */
public final class Report {

    private final ReportHeader header;
    private final SampleWindow window;
    private final List<Assessment> measures;
    private final String trend;

    /**
     * Full constructor.
     *
     * @param header report metadata
     * @param window the assessed window
     * @param measures assessed levels in display order
     * @param trend one of the {@link com.cistern.model.Trend} labels
     */
    public Report(ReportHeader header, SampleWindow window,
                  List<Assessment> measures, String trend) {
        this.header = header;
        this.window = window;
        this.measures = new ArrayList<>(measures);
        this.trend = trend;
    }

    public ReportHeader header() {
        return header;
    }

    public SampleWindow window() {
        return window;
    }

    /** Defensive copy of the assessed measures in display order. */
    public List<Assessment> measures() {
        return new ArrayList<>(measures);
    }

    public String trend() {
        return trend;
    }

    /**
     * Wall-clock span of the assessed window (max minus min timestamp).
     *
     * @return span in millis, or 0 for a window with fewer than two samples
     */
    public long windowSpanMillis() {
        if (window.size() < 2) {
            return 0L;
        }
        long minimum = Long.MAX_VALUE;
        long maximum = Long.MIN_VALUE;
        for (Sample sample : window.samples()) {
            minimum = Math.min(minimum, sample.timestampMillis());
            maximum = Math.max(maximum, sample.timestampMillis());
        }
        return maximum - minimum;
    }

    /** The measure with the given code, if present. */
    public Optional<Assessment> measure(String code) {
        for (Assessment assessment : measures) {
            if (assessment.code().equals(code)) {
                return Optional.of(assessment);
            }
        }
        return Optional.empty();
    }

    /**
     * Ordered map view used by the JSON renderer and by callers that want the
     * structure without the serialisation.
     *
     * @return a nested map in stable key order
     */
    public LinkedHashMap<String, Object> toMap() {
        LinkedHashMap<String, Object> root = new LinkedHashMap<>();
        LinkedHashMap<String, Object> headerMap = new LinkedHashMap<>();
        headerMap.put("station", header.stationId());
        headerMap.put("report_id", header.reportId());
        headerMap.put("generated_at", header.generatedAtMillis());
        headerMap.put("generator", header.generator());
        root.put("header", headerMap);
        LinkedHashMap<String, Object> windowMap = new LinkedHashMap<>();
        windowMap.put("samples", window.size());
        windowMap.put("min", window.min());
        windowMap.put("max", window.max());
        windowMap.put("mean", window.mean());
        root.put("window", windowMap);
        LinkedHashMap<String, Object> measuresMap = new LinkedHashMap<>();
        for (Assessment assessment : measures) {
            LinkedHashMap<String, Object> measure = new LinkedHashMap<>();
            measure.put("level", assessment.level());
            measure.put("severity", assessment.severity().code());
            measure.put("method", assessment.method());
            measuresMap.put(assessment.code(), measure);
        }
        root.put("measures", measuresMap);
        root.put("trend", trend);
        return root;
    }
}
'''

FILES[f"{SRC}/com/cistern/report/ReportBuilder.java"] = '''package com.cistern.report;

import com.cistern.core.AssessmentEngine;
import com.cistern.core.AssessmentValidator;
import com.cistern.core.AssessorRegistry;
import com.cistern.model.Assessment;
import com.cistern.model.ReportHeader;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import com.cistern.model.Trend;
import java.util.ArrayList;
import java.util.List;

/**
 * Assembles a {@link Report} from one window and one or more level strategies.
 *
 * <p>The builder is a consumer of the {@link com.cistern.core.LevelAssessor}
 * contract: strategies are resolved by code through the registry and always
 * invoked through the interface, never as concrete classes. That is what lets
 * the core module evolve its estimators without this module changing.
 */
public final class ReportBuilder {

    private final AssessmentEngine engine;

    public ReportBuilder() {
        this.engine = new AssessmentEngine();
    }

    /**
     * Builds a report containing a single strategy.
     *
     * @param header report metadata
     * @param window the window to assess
     * @param threshold capacity and band boundaries
     * @param code strategy code
     * @return a report with exactly one measure
     */
    public Report buildSingle(ReportHeader header, SampleWindow window,
                              Threshold threshold, String code) {
        List<Assessment> measures = new ArrayList<>();
        measures.add(engine.evaluate(window, threshold, code));
        AssessmentValidator.requireValid(measures);
        return new Report(header, window, measures, trendOf(window));
    }

    /**
     * Builds a report containing every registered strategy.
     *
     * @param header report metadata
     * @param window the window to assess
     * @param threshold capacity and band boundaries
     * @return a report with one measure per registered strategy
     */
    public Report buildAll(ReportHeader header, SampleWindow window, Threshold threshold) {
        List<Assessment> measures = new ArrayList<>();
        for (String code : AssessorRegistry.codes()) {
            measures.add(engine.evaluate(window, threshold, code));
        }
        AssessmentValidator.requireValid(measures);
        return new Report(header, window, measures, trendOf(window));
    }

    /**
     * Compares the mean of the first half of the window with the mean of the
     * second half to derive a one-word trend label.
     *
     * @param window the window to compare against itself
     * @return a {@link Trend} label
     */
    public static String trendOf(SampleWindow window) {
        if (window.size() < 2) {
            return Trend.FLAT.label();
        }
        double[] litres = window.valuesLitres();
        int half = window.size() / 2;
        double first = meanLitres(litres, 0, half);
        double second = meanLitres(litres, half, litres.length);
        return Trend.between(first, second).label();
    }

    static double meanLitres(double[] values, int from, int to) {
        double sum = 0.0;
        for (int i = from; i < to; i++) {
            sum += values[i];
        }
        return (to > from) ? sum / (to - from) : 0.0;
    }
}
'''

FILES[f"{SRC}/com/cistern/report/TextReportRenderer.java"] = '''package com.cistern.report;

import com.cistern.model.Assessment;
import com.cistern.model.ReportHeader;
import java.util.Locale;

/**
 * Renders a {@link Report} as a fixed-width text table suitable for terminals
 * and log files.
 */
public final class TextReportRenderer {

    /**
     * Renders the report as text.
     *
     * @param report the structured report
     * @return multi-line text ending with a newline
     */
    public String render(Report report) {
        StringBuilder out = new StringBuilder();
        ReportHeader header = report.header();
        out.append("Cistern level report ").append(header.reportId()).append('\\n');
        out.append("station: ").append(header.stationId()).append('\\n');
        out.append("generated: ").append(header.generatedAtMillis()).append('\\n');
        out.append("window: ").append(report.window().size()).append(" samples, trend ")
           .append(report.trend()).append('\\n');
        out.append(String.format(Locale.ROOT, "%-10s %-8s %-9s %s%n",
                "measure", "level", "severity", "method"));
        for (Assessment assessment : report.measures()) {
            out.append(String.format(Locale.ROOT, "%-10s %-8.4f %-9s %s%n",
                    assessment.code(), assessment.level(),
                    assessment.severity().code(), assessment.method()));
        }
        if (!report.measures().isEmpty()) {
            out.append("levels:        ")
               .append(Sparklines.levelBar(report.measures().get(0).level(), 24))
               .append('\\n');
        }
        out.append("window:        ").append(Sparklines.sparkline(report.window(), 24))
           .append("  (span ").append(com.cistern.model.DurationFormat.format(report.windowSpanMillis()))
           .append(")\\n");
        return out.toString();
    }
}
'''

FILES[f"{SRC}/com/cistern/report/JsonReportRenderer.java"] = '''package com.cistern.report;

import com.cistern.model.JsonCodec;

/**
 * Renders a {@link Report} as a single-line JSON object.
 *
 * <p>The serialisation is deterministic: the same data always produces the
 * same bytes, which keeps stored reports diffable and testable.
 */
public final class JsonReportRenderer {

    /**
     * Renders the report as JSON text.
     *
     * @param report the structured report
     * @return compact one-line JSON with stable key order
     */
    public String render(Report report) {
        return JsonCodec.writeObject(report.toMap());
    }
}
'''

FILES[f"{SRC}/com/cistern/report/LabelTable.java"] = '''package com.cistern.report;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Display labels for the measure codes rendered into reports and CLI output.
 *
 * <p>The table is keyed by the strategy {@code code()} values; an unknown code
 * passes through unchanged so a future strategy never crashes a report just
 * because this table was not updated.
 */
public final class LabelTable {

    private static final Map<String, String> LABELS = labels();

    private LabelTable() {
        // utility class
    }

    private static Map<String, String> labels() {
        LinkedHashMap<String, String> labels = new LinkedHashMap<>();
        labels.put("baseline", "Baseline level");
        labels.put("peak", "Peak level");
        labels.put("trough", "Trough level");
        labels.put("drift", "Range width");
        labels.put("stability", "Stability score");
        labels.put("surge", "Surge margin");
        return labels;
    }

    /**
     * Label for a strategy code.
     *
     * @param code the strategy code
     * @return the display label, or the code itself when unknown
     */
    public static String label(String code) {
        String label = LABELS.get(code);
        return label == null ? code : label;
    }

    /** All labels in registration order. */
    public static Map<String, String> all() {
        return new LinkedHashMap<>(LABELS);
    }
}
'''

FILES[f"{SRC}/com/cistern/report/ReportPipeline.java"] = '''package com.cistern.report;

import com.cistern.core.AssessorRegistry;
import com.cistern.core.LevelAssessor;
import com.cistern.model.Assessment;
import com.cistern.model.ReportHeader;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import java.util.Map;

/**
 * High-level entry point used by the CLI and by integration tests.
 *
 * <p>Everything here flows through the {@link LevelAssessor} interface: a
 * strategy is resolved by code, run over the window and decorated with its
 * severity band before being rendered. The pipeline is deliberately thin -
 * it exists so callers never need to know the strategy classes at all.
 */
public final class ReportPipeline {

    private final ReportBuilder builder = new ReportBuilder();
    private final JsonReportRenderer json = new JsonReportRenderer();

    /**
     * Resolves a strategy by code.
     *
     * @param code strategy code
     * @return the strategy instance; the baseline default when unknown
     */
    public LevelAssessor assessorFor(String code) {
        return AssessorRegistry.byCode(code);
    }

    /**
     * Runs a single-strategy assessment and returns the record.
     *
     * @param code strategy code
     * @param window window to assess
     * @param threshold capacity and band boundaries
     * @return the assessment record
     * @throws IllegalStateException when the report pipeline did not produce
     *     the requested measure (only possible for unknown codes)
     */
    public Assessment assess(String code, SampleWindow window, Threshold threshold) {
        return builder.buildSingle(ReportHeader.now("pipeline"), window, threshold, code)
                .measure(code)
                .orElseThrow(() -> new IllegalStateException(
                        "measure " + code + " missing from report"));
    }

    /**
     * Renders a single-strategy report as JSON text.
     *
     * @param code strategy code
     * @param window window to assess
     * @param threshold capacity and band boundaries
     * @return a deterministic one-line JSON object
     */
    public String renderJson(String code, SampleWindow window, Threshold threshold) {
        ReportHeader header = ReportHeader.now("pipeline");
        return json.render(builder.buildSingle(header, window, threshold, code));
    }

    /**
     * Renders a single-strategy report as a structured map.
     *
     * @param code strategy code
     * @param window window to assess
     * @param threshold capacity and band boundaries
     * @return the report as a nested map in stable key order
     */
    public Map<String, Object> renderMap(String code, SampleWindow window, Threshold threshold) {
        ReportHeader header = ReportHeader.now("pipeline");
        return builder.buildSingle(header, window, threshold, code).toMap();
    }
}
'''
FILES[f"{SRC}/com/cistern/report/Sparklines.java"] = '''package com.cistern.report;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;

/**
 * Tiny ASCII sparklines for terminal reports.
 *
 * <p>The text renderer appends a {@link #levelBar(double, int)} for the first
 * measure and a {@link #sparkline(SampleWindow, int)} of the window values, so
 * heights can be eyeballed in logs without parsing numbers.
 */
public final class Sparklines {

    private Sparklines() {
        // utility class
    }

    /**
     * A fixed-width bar of a level fraction, e.g. {@code "******...."}.
     *
     * @param level level fraction, saturated into {@code [0, 1]}
     * @param width total width of the bar
     * @return a string of stars and dots of exactly {@code width} characters
     */
    public static String levelBar(double level, int width) {
        int filled = (int) Math.round(LevelMath.clamp01(level) * width);
        filled = Math.max(0, Math.min(width, filled));
        return "*".repeat(filled) + ".".repeat(width - filled);
    }

    /**
     * A sparkline of the window values, scaled to the window's own range.
     *
     * @param window the window to draw
     * @param width number of columns in the output
     * @return a string of exactly {@code width} glyphs
     */
    public static String sparkline(SampleWindow window, int width) {
        if (width <= 0) {
            return "";
        }
        if (window.isEmpty()) {
            return " ".repeat(width);
        }
        double[] values = window.values();
        double min = window.min();
        double max = window.max();
        double span = max - min;
        StringBuilder out = new StringBuilder(width);
        for (int i = 0; i < width; i++) {
            int from = i * values.length / width;
            int to = (i + 1) * values.length / width;
            double sum = 0.0;
            for (int j = from; j < to; j++) {
                sum += values[j];
            }
            double mean = (to > from) ? sum / (to - from) : values[values.length - 1];
            double fraction = (span == 0.0) ? 1.0 : (mean - min) / span;
            if (fraction < 0.25) {
                out.append(' ');
            } else if (fraction < 0.5) {
                out.append(':');
            } else if (fraction < 0.75) {
                out.append('|');
            } else {
                out.append('*');
            }
        }
        return out.toString();
    }
}
'''

FILES[f"{SRC}/com/cistern/report/ReportComparator.java"] = '''package com.cistern.report;

import com.cistern.model.Assessment;
import com.cistern.model.JsonCodec;
import java.util.LinkedHashMap;
import java.util.Optional;

/**
 * Compares two reports measure by measure.
 *
 * <p>Used by operational tooling to answer "what changed between this week's
 * window and last week's" and by tests to pin that a refactor left levels
 * untouched. Only the level fractions are compared; headers and windows are
 * ignored.
 */
public final class ReportComparator {

    /** Tolerance under which a delta counts as unchanged. */
    public static final double DEFAULT_TOLERANCE = 1e-9;

    private ReportComparator() {
        // utility class
    }

    /**
     * Per-code level delta of {@code after} minus {@code before}.
     *
     * @param before the earlier report
     * @param after the later report
     * @return an ordered map of measure code to delta; codes only in
     *     {@code before} map to NaN
     */
    public static LinkedHashMap<String, Double> levelDeltas(Report before, Report after) {
        LinkedHashMap<String, Double> deltas = new LinkedHashMap<>();
        for (Assessment assessment : before.measures()) {
            Optional<Assessment> counterpart = after.measure(assessment.code());
            double delta = counterpart.map(next -> next.level() - assessment.level())
                    .orElse(Double.NaN);
            deltas.put(assessment.code(), delta);
        }
        return deltas;
    }

    /**
     * Human-readable delta summary, e.g. {@code "baseline=0.05 peak=0"}.
     *
     * @param before the earlier report
     * @param after the later report
     * @return a space-joined {@code code=delta} description
     */
    public static String describe(Report before, Report after) {
        StringBuilder out = new StringBuilder();
        for (var entry : levelDeltas(before, after).entrySet()) {
            if (out.length() > 0) {
                out.append(' ');
            }
            out.append(entry.getKey()).append('=').append(JsonCodec.formatNumber(entry.getValue()));
        }
        return out.toString();
    }

    /**
     * Whether every shared measure has the same level within tolerance.
     *
     * @param before the earlier report
     * @param after the later report
     * @return true when no shared measure moved
     */
    public static boolean levelsUnchanged(Report before, Report after) {
        for (double delta : levelDeltas(before, after).values()) {
            if (Double.isNaN(delta) || Math.abs(delta) > DEFAULT_TOLERANCE) {
                return false;
            }
        }
        return true;
    }
}
'''
