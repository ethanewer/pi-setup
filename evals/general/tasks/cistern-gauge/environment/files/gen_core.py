# -*- coding: utf-8 -*-
"""Sources for the cistern-core module (com.cistern.core).

Part of the cistern-gauge fixture generator.
"""

SRC = "cistern-core/src/main/java"

FILES = {}

FILES[f"{SRC}/com/cistern/core/LevelAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Strategy contract for computing a reservoir level from a window of samples.
 *
 * <p>Every strategy converts the samples in a {@link SampleWindow} into a
 * single level fraction in {@code [0, 1]} relative to the {@link Threshold}
 * capacity. Strategies must be pure: the same window and threshold always
 * produce the same level, and calling {@link #assess} must never mutate the
 * window.
 *
 * <p>This interface is the boundary the other modules - in particular the
 * report module - rely on. The {@link #code()} values are stable deployment
 * keys: renaming one, or changing this interface's shape, breaks every
 * downstream consumer that is only aware of the interface.
 */
public interface LevelAssessor {

    /**
     * Computes the level fraction for the window.
     *
     * @param window sample window captured from the monitor
     * @param threshold capacity and band boundaries of the reservoir
     * @return level fraction in the closed range {@code [0, 1]}
     */
    double assess(SampleWindow window, Threshold threshold);

    /**
     * Stable registry key of this strategy, e.g. {@code "baseline"}.
     *
     * @return the code configuration files use to select this strategy
     */
    String code();

    /**
     * Human description of the strategy and its estimator.
     *
     * @return a sentence suitable for reports and CLI output
     */
    String describe();
}
'''

FILES[f"{SRC}/com/cistern/core/BaselineAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Baseline level strategy.
 *
 * <p>The baseline strategy measures how full a reservoir is by comparing the
 * central tendency of the captured window with the reservoir capacity. The
 * estimator used as the central tendency is the <strong>arithmetic mean</strong>
 * of the sample values.
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
        return "Baseline level estimate (arithmetic mean of window)";
    }

    /**
     * Central tendency of the window values used as the baseline estimate.
     * The operation is the arithmetic mean of the values; empty windows
     * estimate 0.
     *
     * @param values litre-normalised sample values, in capture order
     * @return the central tendency of the values
     */
    private static double centralEstimate(double[] values) {
        double sum = 0.0;
        for (double value : values) {
            sum += value;
        }
        return values.length == 0 ? 0.0 : sum / values.length;
    }
}
'''

FILES[f"{SRC}/com/cistern/core/PeakAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Peak level strategy.
 *
 * <p>Reports the highest sample in the window as the level: the reservoir is
 * judged by its maximum, which makes this strategy sensitive to surges and
 * refill activity while the baseline strategy stays calm.
 */
public final class PeakAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        if (window.isEmpty()) {
            return 0.0;
        }
        double peakLitres = 0.0;
        for (double value : window.valuesLitres()) {
            peakLitres = Math.max(peakLitres, value);
        }
        return LevelMath.clamp01(peakLitres / threshold.capacity());
    }

    @Override
    public String code() {
        return "peak";
    }

    @Override
    public String describe() {
        return "Peak level estimate (maximum of window)";
    }
}
'''

FILES[f"{SRC}/com/cistern/core/TroughAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Trough level strategy.
 *
 * <p>Reports the lowest sample in the window as the level. Negative minima -
 * which happen when the field instruments emit deltas - saturate to the
 * zero-level band rather than producing a nonsensical negative level.
 */
public final class TroughAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        if (window.isEmpty()) {
            return 0.0;
        }
        double minLitres = Double.POSITIVE_INFINITY;
        for (double value : window.valuesLitres()) {
            minLitres = Math.min(minLitres, value);
        }
        return LevelMath.clamp01(minLitres / threshold.capacity());
    }

    @Override
    public String code() {
        return "trough";
    }

    @Override
    public String describe() {
        return "Trough level estimate (minimum of window)";
    }
}
'''

FILES[f"{SRC}/com/cistern/core/DriftAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Drift level strategy.
 *
 * <p>Reports the spread of the window - its range, max minus min - relative
 * to capacity. A wide window produces a high figure: the strategy is an
 * indicator of how much the level moved while the window was being captured,
 * which is useful for diagnosing leaks and refill cycles.
 */
public final class DriftAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        if (window.isEmpty()) {
            return 0.0;
        }
        double minimum = Double.POSITIVE_INFINITY;
        double maximum = Double.NEGATIVE_INFINITY;
        for (double value : window.valuesLitres()) {
            minimum = Math.min(minimum, value);
            maximum = Math.max(maximum, value);
        }
        return LevelMath.clamp01((maximum - minimum) / threshold.capacity());
    }

    @Override
    public String code() {
        return "drift";
    }

    @Override
    public String describe() {
        return "Drift level estimate (range of window)";
    }
}
'''

FILES[f"{SRC}/com/cistern/core/StabilityAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Stability strategy.
 *
 * <p>Scores the window by how little it deviates: {@code 1 - stdev/capacity},
 * so a completely calm window scores the full band and a window spread over
 * the whole capacity scores near zero. Windows with fewer than two samples
 * are perfectly stable by definition.
 */
public final class StabilityAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        if (window.size() < 2) {
            return 1.0;
        }
        double deviation = window.standardDeviation();
        return LevelMath.clamp01(1.0 - deviation / threshold.capacity());
    }

    @Override
    public String code() {
        return "stability";
    }

    @Override
    public String describe() {
        return "Stability score (inverse deviation of window)";
    }
}
'''

FILES[f"{SRC}/com/cistern/core/SurgeAssessor.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Surge strategy.
 *
 * <p>Compares the mean of the most recent quarter of the window with the mean
 * of the whole window. A positive gap means the level is climbing faster than
 * the window's own recent past - the signature of an active refill - and is
 * reported as the level, saturating at capacity.
 */
public final class SurgeAssessor implements LevelAssessor {

    @Override
    public double assess(SampleWindow window, Threshold threshold) {
        double[] litres = window.valuesLitres();
        if (litres.length == 0) {
            return 0.0;
        }
        int recentStart = litres.length - Math.max(1, litres.length / 4);
        double recentMean = meanLitres(java.util.Arrays.copyOfRange(litres, recentStart, litres.length));
        double wholeMean = meanLitres(litres);
        return LevelMath.clamp01((recentMean - wholeMean) / threshold.capacity());
    }

    @Override
    public String code() {
        return "surge";
    }

    @Override
    public String describe() {
        return "Surge level estimate (recent quarter vs window mean)";
    }

    private static double meanLitres(double[] values) {
        double sum = 0.0;
        for (double value : values) {
            sum += value;
        }
        return values.length == 0 ? 0.0 : sum / values.length;
    }
}
'''

FILES[f"{SRC}/com/cistern/core/AssessorRegistry.java"] = '''package com.cistern.core;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Named lookup of the shipped level strategies.
 *
 * <p>Configuration and the report pipeline address strategies by their stable
 * {@link LevelAssessor#code() code}; this registry is the single place that
 * maps codes to implementations. Unknown codes resolve to the default
 * {@link BaselineAssessor baseline} strategy so a stale configuration degrades
 * into a safe, sensible level instead of failing the whole pipeline.
 */
public final class AssessorRegistry {

    private AssessorRegistry() {
        // utility class
    }

    /**
     * Resolves a strategy by code.
     *
     * @param code configuration key, may be {@code null}
     * @return a fresh strategy instance; the default baseline when unknown
     */
    public static LevelAssessor byCode(String code) {
        if (code == null) {
            return new BaselineAssessor();
        }
        switch (code) {
            case "baseline":
                return new BaselineAssessor();
            case "peak":
                return new PeakAssessor();
            case "trough":
                return new TroughAssessor();
            case "drift":
                return new DriftAssessor();
            case "stability":
                return new StabilityAssessor();
            case "surge":
                return new SurgeAssessor();
            default:
                return new BaselineAssessor();
        }
    }

    /**
     * All registered codes in a stable registration order.
     *
     * @return an immutable set of the strategy codes
     */
    public static Set<String> codes() {
        LinkedHashSet<String> codes = new LinkedHashSet<>();
        codes.add("baseline");
        codes.add("peak");
        codes.add("trough");
        codes.add("drift");
        codes.add("stability");
        codes.add("surge");
        return codes;
    }

    /** Whether the registry contains the code. */
    public static boolean contains(String code) {
        return codes().contains(code);
    }
}
'''

FILES[f"{SRC}/com/cistern/core/AssessmentEngine.java"] = '''package com.cistern.core;

import com.cistern.model.Assessment;
import com.cistern.model.SampleWindow;
import com.cistern.model.Severity;
import com.cistern.model.Threshold;

/**
 * Orchestrates a single assessment: resolves the named strategy, runs it over
 * the window and decorates the resulting level fraction with its severity
 * band.
 *
 * <p>The engine talks to strategies exclusively through the
 * {@link LevelAssessor} interface, so a strategy can be swapped, replaced or
 * re-estimated without touching anything above this class.
 */
public final class AssessmentEngine {

    /**
     * Runs the strategy named by {@code code} and wraps the result.
     *
     * @param window sample window to assess
     * @param threshold capacity and band boundaries
     * @param code strategy code; unknown codes resolve to the baseline default
     * @return the assessment record
     */
    public Assessment evaluate(SampleWindow window, Threshold threshold, String code) {
        LevelAssessor assessor = AssessorRegistry.byCode(code);
        return evaluate(assessor, window, threshold);
    }

    /**
     * Runs an already-resolved strategy instance and wraps the result.
     *
     * @param assessor strategy instance to run
     * @param window sample window to assess
     * @param threshold capacity and band boundaries
     * @return the assessment record
     */
    public Assessment evaluate(LevelAssessor assessor, SampleWindow window, Threshold threshold) {
        double level = assessor.assess(window, threshold);
        Severity severity = threshold.severityOfFraction(level);
        return Assessment.of(assessor.code(), assessor.describe(), level, severity);
    }
}
'''

FILES[f"{SRC}/com/cistern/core/BaselineTables.java"] = '''package com.cistern.core;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Baseline expectation tables used for calibration and drift diagnosis.
 *
 * <p>The tables describe the fraction of nominal rate expected for each hour
 * of the day at a typical site: quiet night filling, a strong morning draw,
 * steady daytime use. They are informational helpers for the {@code inspect}
 * CLI command; no strategy's level depends on them, so editing them never
 * changes an assessment.
 */
public final class BaselineTables {

    private BaselineTables() {
        // utility class
    }

    /** Hour (0-23) to the expected fill fraction of the nominal rate. */
    public static Map<Integer, Double> hourlyFillFraction() {
        LinkedHashMap<Integer, Double> hourly = new LinkedHashMap<>();
        for (int hour = 0; hour < 24; hour++) {
            double fraction;
            if (hour < 2 || hour >= 22) {
                fraction = 0.90;
            } else if (hour < 6) {
                fraction = 0.70;
            } else if (hour < 10) {
                fraction = 0.35;
            } else if (hour < 18) {
                fraction = 0.50;
            } else {
                fraction = 0.80;
            }
            hourly.put(hour, fraction);
        }
        return hourly;
    }

    /** Seasonal multipliers keyed by month number (1-12). */
    public static Map<Integer, Double> seasonalMultiplier() {
        LinkedHashMap<Integer, Double> monthly = new LinkedHashMap<>();
        monthly.put(1, 1.10);
        monthly.put(2, 1.08);
        monthly.put(3, 1.04);
        monthly.put(4, 0.98);
        monthly.put(5, 0.95);
        monthly.put(6, 0.92);
        monthly.put(7, 0.90);
        monthly.put(8, 0.91);
        monthly.put(9, 0.95);
        monthly.put(10, 1.00);
        monthly.put(11, 1.05);
        monthly.put(12, 1.10);
        return monthly;
    }

    /**
     * Combined expected fill fraction for a moment in time.
     *
     * @param hourOfDay hour in {@code [0, 23]}
     * @param month month number in {@code [1, 12]}
     * @return a fraction in {@code [0, 1]}
     */
    public static double expectedFillFraction(int hourOfDay, int month) {
        double hourly = hourlyFillFraction().getOrDefault(hourOfDay, 0.5);
        double seasonal = seasonalMultiplier().getOrDefault(month, 1.0);
        return Math.max(0.0, Math.min(1.0, hourly * seasonal));
    }
}
'''
FILES[f"{SRC}/com/cistern/core/Calibration.java"] = '''package com.cistern.core;

import com.cistern.model.LevelMath;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;

/**
 * Calibration diagnostics: how far the measured level of a window is from the
 * seasonal expectation tables.
 *
 * <p>{@link #meanResidual(SampleWindow)} compares each sample's measured
 * fraction of capacity with the {@link BaselineTables expected fraction} for
 * the same moment in time and averages the absolute differences. A well
 * calibrated site sits near zero; a persistent positive residual flags that
 * the site is systematically fuller than the model assumes.
 */
public final class Calibration {

    private final double capacityLitres;

    public Calibration(double capacityLitres) {
        if (!(capacityLitres > 0.0) || !Double.isFinite(capacityLitres)) {
            throw new IllegalArgumentException("capacity must be finite and positive");
        }
        this.capacityLitres = capacityLitres;
    }

    /**
     * Mean absolute residual between measured and expected fill fractions.
     *
     * @param window the window to calibrate
     * @return a non-negative fraction, 0 for an empty window or a perfect fit
     */
    public double meanResidual(SampleWindow window) {
        if (window.isEmpty()) {
            return 0.0;
        }
        double total = 0.0;
        int count = 0;
        for (Sample sample : window.samples()) {
            double measuredFraction = LevelMath.clamp01(sample.valueLitres() / capacityLitres);
            ZonedDateTime when = ZonedDateTime.ofInstant(
                    Instant.ofEpochMilli(sample.timestampMillis()), ZoneOffset.UTC);
            double expected = BaselineTables.expectedFillFraction(when.getHour(), when.getMonthValue());
            total += Math.abs(measuredFraction - expected);
            count++;
        }
        return count == 0 ? 0.0 : total / count;
    }

    /**
     * How many samples fall within {@code tolerance} of the expectation.
     *
     * @param window the window to calibrate
     * @param tolerance absolute residual accepted as "in spec"
     * @return the count of in-spec samples
     */
    public long inSpecSamples(SampleWindow window, double tolerance) {
        long count = 0;
        for (Sample sample : window.samples()) {
            double measuredFraction = LevelMath.clamp01(sample.valueLitres() / capacityLitres);
            ZonedDateTime when = ZonedDateTime.ofInstant(
                    Instant.ofEpochMilli(sample.timestampMillis()), ZoneOffset.UTC);
            double expected = BaselineTables.expectedFillFraction(when.getHour(), when.getMonthValue());
            if (Math.abs(measuredFraction - expected) <= tolerance) {
                count++;
            }
        }
        return count;
    }
}
'''

FILES[f"{SRC}/com/cistern/core/ConfidenceBand.java"] = '''package com.cistern.core;

import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;

/**
 * Approximate confidence band around an assessed level.
 *
 * <p>The band models the sampling error of the estimator: its half-width is
 * {@code 1.96 * stdev / sqrt(n)} relative to capacity, the usual 95% half
 * width of a mean under the normal approximation. Assessors and the CLI
 * report the band as context; it never changes the level itself.
 */
public final class ConfidenceBand {

    private final double center;
    private final double halfWidth;

    public ConfidenceBand(double center, double halfWidth) {
        this.center = center;
        this.halfWidth = Math.max(0.0, halfWidth);
    }

    /**
     * Computes the band for a strategy over a window and threshold.
     *
     * @param assessor the strategy to run
     * @param window the window to assess
     * @param threshold capacity and band boundaries
     * @return the band centred on the assessed level
     */
    public static ConfidenceBand of(LevelAssessor assessor, SampleWindow window, Threshold threshold) {
        double level = assessor.assess(window, threshold);
        double halfWidth;
        if (window.size() < 2) {
            halfWidth = 0.0;
        } else {
            double standardError = window.standardDeviation() / Math.sqrt(window.size());
            halfWidth = 1.96 * standardError / threshold.capacity();
        }
        return new ConfidenceBand(level, halfWidth);
    }

    public double center() {
        return center;
    }

    /** Lower bound, saturated at zero. */
    public double lower() {
        return Math.max(0.0, center - halfWidth);
    }

    /** Upper bound, saturated at one. */
    public double upper() {
        return Math.min(1.0, center + halfWidth);
    }

    public double halfWidth() {
        return halfWidth;
    }
}
'''

FILES[f"{SRC}/com/cistern/core/AssessmentValidator.java"] = '''package com.cistern.core;

import com.cistern.model.Assessment;
import com.cistern.model.Severity;
import java.util.ArrayList;
import java.util.List;

/**
 * Structural invariants of an assessment.
 *
 * <p>The engine guarantees most of these by construction; the validator is
 * the belt-and-braces guard the report builder runs before assembling a
 * report, so a malformed strategy can never corrupt stored output. It reports
 * every problem found instead of stopping at the first.
 */
public final class AssessmentValidator {

    /** Tolerance around the level band that still counts as valid. */
    public static final double LEVEL_TOLERANCE = 1e-9;

    private AssessmentValidator() {
        // utility class
    }

    /**
     * Checks one assessment.
     *
     * @param assessment the assessment to inspect
     * @return a list of human-readable problems; empty when valid
     */
    public static List<String> problems(Assessment assessment) {
        List<String> problems = new ArrayList<>();
        if (assessment == null) {
            problems.add("assessment is null");
            return problems;
        }
        if (assessment.code() == null || assessment.code().isBlank()) {
            problems.add("assessment code is blank");
        }
        if (assessment.method() == null || assessment.method().isBlank()) {
            problems.add("assessment method is blank");
        }
        if (!Double.isFinite(assessment.level())) {
            problems.add("assessment level is not finite: " + assessment.level());
        } else if (assessment.level() < -LEVEL_TOLERANCE || assessment.level() > 1.0 + LEVEL_TOLERANCE) {
            problems.add("assessment level out of band: " + assessment.level());
        }
        if (assessment.severity() == null) {
            problems.add("assessment severity is null");
        }
        return problems;
    }

    /**
     * Checks every assessment in a list.
     *
     * @param assessments the assessments to inspect
     * @return the concatenated problems, empty when all are valid
     */
    public static List<String> problems(List<Assessment> assessments) {
        List<String> problems = new ArrayList<>();
        if (assessments == null) {
            problems.add("assessment list is null");
            return problems;
        }
        for (Assessment assessment : assessments) {
            problems.addAll(problems(assessment));
        }
        return problems;
    }

    /**
     * Throws when any assessment violates the invariants.
     *
     * @param assessments the assessments to inspect
     * @throws IllegalStateException with the joined problems when invalid
     */
    public static void requireValid(List<Assessment> assessments) {
        List<String> problems = problems(assessments);
        if (!problems.isEmpty()) {
            throw new IllegalStateException("invalid assessment(s): " + String.join("; ", problems));
        }
    }

    /**
     * Builds a severity constant for the level, for cross-checking callers.
     *
     * @param level the level fraction
     * @return the severity the band implies
     */
    public static Severity severityForLevel(double level) {
        if (level >= 1.0) {
            return Severity.CRITICAL;
        }
        if (level >= 0.85) {
            return Severity.ALERT;
        }
        if (level >= 0.60) {
            return Severity.WARN;
        }
        return Severity.NOMINAL;
    }
}
'''

FILES[f"{SRC}/com/cistern/core/AssessmentHistory.java"] = '''package com.cistern.core;

import com.cistern.model.JsonCodec;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Bounded history of recent assessment snapshots.
 *
 * <p>The CLI keeps a rolling history of the per-strategy levels so an
 * operator can eyeball the latest states at a glance. The history is
 * append-only and evicts the oldest entry once it exceeds its capacity.
 */
public final class AssessmentHistory {

    /** One recorded snapshot. */
    public record Entry(String code, double level) {

        public Entry {
            if (code == null || code.isBlank()) {
                throw new IllegalArgumentException("entry code must not be blank");
            }
        }
    }

    private final int capacity;
    private final ArrayDeque<Entry> entries;

    public AssessmentHistory(int capacity) {
        if (capacity < 1) {
            throw new IllegalArgumentException("capacity must be positive: " + capacity);
        }
        this.capacity = capacity;
        this.entries = new ArrayDeque<>();
    }

    /**
     * Records a snapshot and returns {@code this} for fluent call sites.
     *
     * @param code strategy code
     * @param level level fraction
     * @return this history
     */
    public AssessmentHistory record(String code, double level) {
        entries.addLast(new Entry(code, level));
        while (entries.size() > capacity) {
            entries.removeFirst();
        }
        return this;
    }

    /** Number of snapshots currently retained. */
    public int size() {
        return entries.size();
    }

    /** Defensive copy of the snapshots in chronological order. */
    public List<Entry> entries() {
        return new ArrayList<>(entries);
    }

    /** The most recent snapshot, if any. */
    public Optional<Entry> last() {
        return entries.isEmpty() ? Optional.empty() : Optional.of(entries.getLast());
    }

    /** Whether any retained snapshot carries the code. */
    public boolean containsCode(String code) {
        for (Entry entry : entries) {
            if (entry.code().equals(code)) {
                return true;
            }
        }
        return false;
    }

    /** Comma-joined {@code code=level} snapshots in chronological order. */
    public String summary() {
        StringBuilder out = new StringBuilder();
        for (Entry entry : entries) {
            if (out.length() > 0) {
                out.append(", ");
            }
            out.append(entry.code()).append('=')
               .append(JsonCodec.formatNumber(entry.level()));
        }
        return out.toString();
    }
}
'''
