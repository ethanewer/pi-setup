# -*- coding: utf-8 -*-
"""Sources for the cistern-model module (com.cistern.model).

Part of the cistern-gauge fixture generator. Each module generator exposes
FILES: an ordered mapping of repository-relative path -> file content.
"""

SRC = "cistern-model/src/main/java"

FILES = {}

FILES[f"{SRC}/com/cistern/model/Units.java"] = '''package com.cistern.model;

import java.util.Locale;
import java.util.Optional;

/**
 * Volume units understood by the cistern telemetry stack.
 *
 * <p>Each constant knows its conversion factor to litres so readings captured
 * in one unit can be compared against thresholds expressed in another. The
 * conversion factors follow the internationally standardised values kept in
 * the model module so every downstream strategy aggregates on the same basis.
 */
public enum Units {

    MILLILITRES(0.001, "ml"),
    LITRES(1.0, "l"),
    METRES_CUBED(1000.0, "m3"),
    GALLONS_UK(4.54609, "gal-uk"),
    GALLONS_US(3.78541, "gal-us"),
    BARRELS(158.9873, "bbl"),
    CUBIC_FEET(28.31685, "ft3");

    private final double toLitres;
    private final String symbol;

    Units(double toLitres, String symbol) {
        this.toLitres = toLitres;
        this.symbol = symbol;
    }

    /** Converts an amount expressed in this unit into litres. */
    public double toLitres(double amount) {
        return amount * toLitres;
    }

    /** Converts a litre amount into this unit. */
    public double fromLitres(double litres) {
        return litres / toLitres;
    }

    /** Short display symbol, e.g. {@code "l"} or {@code "gal-us"}. */
    public String symbol() {
        return symbol;
    }

    /** Stable lowercase code used in configuration files and CSVs. */
    public String code() {
        return name().toLowerCase(Locale.ROOT);
    }

    /**
     * Case-insensitive lookup of a unit by its {@link #code() code} or its
     * {@link #symbol() symbol}.
     *
     * @param token candidate code or symbol, may be {@code null}
     * @return the matching unit, or {@link Optional#empty() empty} when unknown
     */
    public static Optional<Units> parse(String token) {
        if (token == null) {
            return Optional.empty();
        }
        String key = token.trim().toLowerCase(Locale.ROOT);
        for (Units unit : values()) {
            if (unit.code().equals(key) || unit.symbol().equals(key)) {
                return Optional.of(unit);
            }
        }
        return Optional.empty();
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Sample.java"] = '''package com.cistern.model;

import java.util.Objects;

/**
 * One measured sample from a reservoir monitor.
 *
 * <p>A sample is an immutable triple of a numeric value, the epoch-millis
 * timestamp at which it was captured and the unit it was captured in. All the
 * downstream statistics work on litre-normalised values, so a sample captured
 * in gallons can sit next to one captured in litres without conversion at the
 * call site.
 *
 * <p>Values may be negative: field instruments produce deltas and offsets, and
 * the level strategies decide how to treat those. Non-finite values are
 * rejected at construction time so no strategy ever has to handle NaN.
 */
public final class Sample {

    private final long timestampMillis;
    private final double value;
    private final Units unit;
    private final String source;

    private Sample(long timestampMillis, double value, Units unit, String source) {
        if (!Double.isFinite(value)) {
            throw new IllegalArgumentException("sample value must be finite: " + value);
        }
        this.timestampMillis = timestampMillis;
        this.value = value;
        this.unit = Objects.requireNonNull(unit, "unit");
        this.source = source == null ? "" : source;
    }

    /**
     * Full factory.
     *
     * @param timestampMillis epoch millis of the reading
     * @param value measured value in {@code unit}
     * @param unit unit of the measured value
     * @param source free-form instrument tag, may be {@code null}
     * @return a new immutable sample
     * @throws IllegalArgumentException when the value is not finite
     */
    public static Sample of(long timestampMillis, double value, Units unit, String source) {
        return new Sample(timestampMillis, value, unit, source);
    }

    /** Helper for call sites working in litres without a source tag. */
    public static Sample litres(long timestampMillis, double litres) {
        return new Sample(timestampMillis, litres, Units.LITRES, "");
    }

    public long timestampMillis() {
        return timestampMillis;
    }

    public double value() {
        return value;
    }

    public Units unit() {
        return unit;
    }

    public String source() {
        return source;
    }

    /** The value normalised into litres regardless of the capture unit. */
    public double valueLitres() {
        return unit.toLitres(value);
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof Sample that)) {
            return false;
        }
        return timestampMillis == that.timestampMillis
                && Double.compare(value, that.value) == 0
                && unit == that.unit
                && source.equals(that.source);
    }

    @Override
    public int hashCode() {
        int result = Long.hashCode(timestampMillis);
        result = 31 * result + Double.hashCode(value);
        result = 31 * result + unit.hashCode();
        result = 31 * result + source.hashCode();
        return result;
    }

    @Override
    public String toString() {
        return "Sample{ts=" + timestampMillis + ", value=" + value
                + " " + unit.code() + ", source='" + source + "'}";
    }
}
'''

FILES[f"{SRC}/com/cistern/model/SampleWindow.java"] = '''package com.cistern.model;

import java.util.Arrays;
import java.util.List;

/**
 * An immutable, ordered collection of {@link Sample samples}.
 *
 * <p>Windows are the unit of analysis for every level strategy in the stack.
 * The class exposes the descriptive statistics the strategies build on - the
 * count, extrema, mean and spread - and always returns defensive copies, so a
 * caller can never mutate a window through a getter.
 *
 * <p>Note that {@link #mean()} is the arithmetic mean; it is a general-purpose
 * statistic of the model module and its semantics must stay that way.
 */
public final class SampleWindow {

    /** Number of samples after which windows are conventionally full. */
    public static final int DEFAULT_CAPACITY = 12;

    private final List<Sample> samples;

    private SampleWindow(List<Sample> samples) {
        this.samples = List.copyOf(samples);
    }

    /** Builds a window from a varargs list of samples. */
    public static SampleWindow of(Sample... samples) {
        return new SampleWindow(Arrays.asList(samples));
    }

    /** Builds a window from a collection; the caller's list is copied. */
    public static SampleWindow of(List<Sample> samples) {
        return new SampleWindow(samples);
    }

    public int size() {
        return samples.size();
    }

    public boolean isEmpty() {
        return samples.isEmpty();
    }

    /** Immutable view of the contained samples. */
    public List<Sample> samples() {
        return samples;
    }

    /** Plain values in capture order, as a defensive copy. */
    public double[] values() {
        double[] out = new double[samples.size()];
        for (int i = 0; i < samples.size(); i++) {
            out[i] = samples.get(i).value();
        }
        return out;
    }

    /** Values converted into litres, in capture order, as a defensive copy. */
    public double[] valuesLitres() {
        double[] out = new double[samples.size()];
        for (int i = 0; i < samples.size(); i++) {
            out[i] = samples.get(i).valueLitres();
        }
        return out;
    }

    /** Smallest sample value; positive infinity for an empty window. */
    public double min() {
        double minimum = Double.POSITIVE_INFINITY;
        for (Sample sample : samples) {
            minimum = Math.min(minimum, sample.value());
        }
        return minimum;
    }

    /** Largest sample value; negative infinity for an empty window. */
    public double max() {
        double maximum = Double.NEGATIVE_INFINITY;
        for (Sample sample : samples) {
            maximum = Math.max(maximum, sample.value());
        }
        return maximum;
    }

    /** Arithmetic mean of the sample values; 0.0 for an empty window. */
    public double mean() {
        if (samples.isEmpty()) {
            return 0.0;
        }
        double sum = 0.0;
        for (Sample sample : samples) {
            sum += sample.value();
        }
        return sum / samples.size();
    }

    /** Population standard deviation; 0.0 for windows with fewer than two samples. */
    public double standardDeviation() {
        if (samples.size() < 2) {
            return 0.0;
        }
        double mean = mean();
        double accumulator = 0.0;
        for (Sample sample : samples) {
            double delta = sample.value() - mean;
            accumulator += delta * delta;
        }
        return Math.sqrt(accumulator / samples.size());
    }

    /** Range (max - min); 0.0 for an empty window. */
    public double range() {
        if (samples.isEmpty()) {
            return 0.0;
        }
        return max() - min();
    }

    /**
     * Nearest-rank percentile of the sample values.
     *
     * @param percentile rank in the inclusive range {@code [0, 100]}
     * @return the value at the computed rank; 0.0 for an empty window
     */
    public double percentile(double percentile) {
        if (samples.isEmpty()) {
            return 0.0;
        }
        double[] sorted = values();
        Arrays.sort(sorted);
        int rank = (int) Math.ceil(percentile / 100.0 * sorted.length) - 1;
        rank = Math.max(0, Math.min(sorted.length - 1, rank));
        return sorted[rank];
    }

    /** Sub-window holding the samples in {@code [from, to)}. */
    public SampleWindow subWindow(int from, int to) {
        return new SampleWindow(samples.subList(from, to));
    }

    /** Whether timestamps are in weakly ascending order across the window. */
    public boolean isChronological() {
        long previous = Long.MIN_VALUE;
        for (Sample sample : samples) {
            if (sample.timestampMillis() < previous) {
                return false;
            }
            previous = sample.timestampMillis();
        }
        return true;
    }

    @Override
    public String toString() {
        return "SampleWindow{size=" + samples.size() + "}";
    }
}
'''

FILES[f"{SRC}/com/cistern/model/LevelMath.java"] = '''package com.cistern.model;

/**
 * Stateless numeric helpers shared by every strategy and threshold.
 *
 * <p>Keeping the clamp semantics here rather than in the strategies makes the
 * saturation rule uniform across the whole stack: a level can never leave the
 * {@code [0, 1]} band, and a NaN input degrades to the safe lower bound.
 */
public final class LevelMath {

    private LevelMath() {
        // utility class
    }

    /** Saturation into {@code [min, max]}; NaN values degrade to {@code min}. */
    public static double clamp(double min, double max, double value) {
        if (Double.isNaN(value)) {
            return min;
        }
        return Math.max(min, Math.min(max, value));
    }

    /** Convenience wrapper for the {@code [0, 1]} band. */
    public static double clamp01(double value) {
        return clamp(0.0, 1.0, value);
    }

    /** True when the value is within machine tolerance of zero. */
    public static boolean nearZero(double value, double tolerance) {
        return Math.abs(value) <= tolerance;
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Threshold.java"] = '''package com.cistern.model;

/**
 * Operational thresholds of a single reservoir.
 *
 * <p>A threshold set pairs a capacity - in litres - with the fractions of
 * that capacity that escalate into the {@link Severity#WARN warn} and
 * {@link Severity#ALERT alert} bands. A level at or above capacity is
 * {@link Severity#CRITICAL critical} by definition.
 */
public final class Threshold {

    private final double capacity;
    private final double warnFraction;
    private final double alertFraction;

    private Threshold(double capacity, double warnFraction, double alertFraction) {
        if (!Double.isFinite(capacity) || capacity <= 0.0) {
            throw new IllegalArgumentException(
                    "capacity must be finite and positive: " + capacity);
        }
        if (!(warnFraction >= 0.0) || !(alertFraction >= 0.0)
                || warnFraction > alertFraction || alertFraction > 1.0) {
            throw new IllegalArgumentException(
                    "fractions must satisfy 0 <= warn <= alert <= 1: "
                            + warnFraction + ", " + alertFraction);
        }
        this.capacity = capacity;
        this.warnFraction = warnFraction;
        this.alertFraction = alertFraction;
    }

    /**
     * Full factory.
     *
     * @param capacity reservoir capacity in litres, positive
     * @param warnFraction fraction of capacity that raises a warning
     * @param alertFraction fraction of capacity that raises an alert
     * @return a new immutable threshold set
     */
    public static Threshold of(double capacity, double warnFraction, double alertFraction) {
        return new Threshold(capacity, warnFraction, alertFraction);
    }

    /** Convenience constructor with the standard 60% warn / 85% alert bands. */
    public static Threshold standard(double capacity) {
        return new Threshold(capacity, 0.60, 0.85);
    }

    public double capacity() {
        return capacity;
    }

    public double warnFraction() {
        return warnFraction;
    }

    public double alertFraction() {
        return alertFraction;
    }

    /** Fraction of capacity occupied by a raw value, saturated into {@code [0, 1]}. */
    public double levelOf(double value) {
        return LevelMath.clamp01(value / capacity);
    }

    /**
     * Severity band for a level fraction.
     *
     * @param fraction a level in {@code [0, 1]}; anything outside is clamped
     * @return the severity band of the fraction
     */
    public Severity severityOfFraction(double fraction) {
        double band = LevelMath.clamp01(fraction);
        if (band >= 1.0) {
            return Severity.CRITICAL;
        }
        if (band >= alertFraction) {
            return Severity.ALERT;
        }
        if (band >= warnFraction) {
            return Severity.WARN;
        }
        return Severity.NOMINAL;
    }

    /** Severity band directly for a raw value in litres. */
    public Severity severityOfValue(double value) {
        return severityOfFraction(levelOf(value));
    }

    @Override
    public String toString() {
        return "Threshold{capacity=" + capacity + ", warn=" + warnFraction
                + ", alert=" + alertFraction + "}";
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Severity.java"] = '''package com.cistern.model;

import java.util.Locale;

/**
 * Operational severity bands used across the whole stack, from model to CLI.
 *
 * <p>The {@link #code()} value is what lands in reports and configuration, so
 * the codes are part of the output contract: changing one ripples through
 * every renderer and every stored record.
 */
public enum Severity {

    NOMINAL("nominal", 0),
    WARN("warn", 1),
    ALERT("alert", 2),
    CRITICAL("critical", 3);

    private final String label;
    private final int rank;

    Severity(String label, int rank) {
        this.label = label;
        this.rank = rank;
    }

    public String label() {
        return label;
    }

    public int rank() {
        return rank;
    }

    /** The stricter of two severities. */
    public static Severity maxOf(Severity first, Severity second) {
        return first.rank >= second.rank ? first : second;
    }

    /** Machine-readable lowercase code. */
    public String code() {
        return name().toLowerCase(Locale.ROOT);
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Trend.java"] = '''package com.cistern.model;

/**
 * Direction of change between two windows or two moments in one window.
 *
 * <p>{@link #between(double, double)} is the comparison the report builder and
 * the CLI use, with a fixed tolerance so tiny jitter never flips a report
 * between rising and falling.
 */
public enum Trend {

    RISING("rising"),
    FALLING("falling"),
    FLAT("flat");

    private final String label;

    Trend(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }

    /** Classifies a signed delta against a tolerance around zero. */
    public static Trend fromDelta(double delta, double tolerance) {
        if (delta > tolerance) {
            return RISING;
        }
        if (delta < -tolerance) {
            return FALLING;
        }
        return FLAT;
    }

    /** Compares two level fractions with a fixed 0.01 tolerance. */
    public static Trend between(double fromLevel, double toLevel) {
        return fromDelta(toLevel - fromLevel, 0.01);
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Reading.java"] = '''package com.cistern.model;

import java.util.Objects;

/**
 * One assessed reading: a raw sample plus the level and severity derived from
 * it against the site threshold.
 *
 * <p>The {@code history} CLI command and the archived stores are built out of
 * these records; the class itself is a plain immutable value holder.
 */
public final class Reading {

    private final Sample sample;
    private final double level;
    private final Severity severity;
    private final String note;

    public Reading(Sample sample, double level, Severity severity, String note) {
        this.sample = Objects.requireNonNull(sample, "sample");
        this.level = level;
        this.severity = Objects.requireNonNull(severity, "severity");
        this.note = note == null ? "" : note;
    }

    /** Factory equivalent of the constructor. */
    public static Reading of(Sample sample, double level, Severity severity, String note) {
        return new Reading(sample, level, severity, note);
    }

    public Sample sample() {
        return sample;
    }

    public double level() {
        return level;
    }

    public Severity severity() {
        return severity;
    }

    public String note() {
        return note;
    }
}
'''

FILES[f"{SRC}/com/cistern/model/ReportHeader.java"] = '''package com.cistern.model;

import java.util.UUID;

/**
 * Metadata repeated atop every rendered report: which station produced it,
 * a unique report id and the generation timestamp.
 *
 * <p>{@link #GENERATOR} identifies the reporting stack version and is part of
 * the machine-readable output, so it must stay in sync with the reactor
 * version in the poms.
 */
public final class ReportHeader {

    public static final String GENERATOR = "cistern-report/1.4.2";

    private final String stationId;
    private final String reportId;
    private final long generatedAtMillis;

    public ReportHeader(String stationId, String reportId, long generatedAtMillis) {
        if (stationId == null || stationId.isBlank()) {
            throw new IllegalArgumentException("station id must not be blank");
        }
        this.stationId = stationId;
        this.reportId = reportId == null || reportId.isBlank()
                ? UUID.randomUUID().toString() : reportId;
        this.generatedAtMillis = generatedAtMillis;
    }

    /** Fresh header with a random report id and the current wall-clock time. */
    public static ReportHeader now(String stationId) {
        return new ReportHeader(stationId, UUID.randomUUID().toString(),
                System.currentTimeMillis());
    }

    public String stationId() {
        return stationId;
    }

    public String reportId() {
        return reportId;
    }

    public long generatedAtMillis() {
        return generatedAtMillis;
    }

    public String generator() {
        return GENERATOR;
    }
}
'''

FILES[f"{SRC}/com/cistern/model/TankSpec.java"] = '''package com.cistern.model;

/**
 * Deployment metadata for one monitored reservoir.
 *
 * <p>Combines the site name, capacity in litres and the band fractions into a
 * single configuration object; {@link #toThreshold()} derives the threshold
 * set the strategies run against.
 */
public final class TankSpec {

    private final String name;
    private final double capacityLitres;
    private final double warnFraction;
    private final double alertFraction;
    private final Units displayUnit;

    public TankSpec(String name, double capacityLitres, double warnFraction,
                    double alertFraction, Units displayUnit) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("name must not be blank");
        }
        if (!(capacityLitres > 0.0) || !Double.isFinite(capacityLitres)) {
            throw new IllegalArgumentException("capacity must be finite and positive");
        }
        if (!(warnFraction >= 0.0) || !(alertFraction >= 0.0)
                || warnFraction > alertFraction || alertFraction > 1.0) {
            throw new IllegalArgumentException("invalid band fractions");
        }
        this.name = name;
        this.capacityLitres = capacityLitres;
        this.warnFraction = warnFraction;
        this.alertFraction = alertFraction;
        this.displayUnit = displayUnit == null ? Units.LITRES : displayUnit;
    }

    /** Convenience constructor with the standard bands and litre display. */
    public static TankSpec standard(String name, double capacityLitres) {
        return new TankSpec(name, capacityLitres, 0.60, 0.85, Units.LITRES);
    }

    public String name() {
        return name;
    }

    public double capacityLitres() {
        return capacityLitres;
    }

    public Units displayUnit() {
        return displayUnit;
    }

    /** The threshold set this spec implies. */
    public Threshold toThreshold() {
        return Threshold.of(capacityLitres, warnFraction, alertFraction);
    }

    /** Formats a litre amount in the display unit, e.g. {@code "250.0 gal-uk"}. */
    public String formatLitres(double litres) {
        return String.format(java.util.Locale.ROOT, "%.1f %s",
                displayUnit.fromLitres(litres), displayUnit.symbol());
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Assessment.java"] = '''package com.cistern.model;

import java.util.Objects;

/**
 * Result of one level assessment: the strategy's stable code, a human
 * description of the estimator, the level fraction in {@code [0, 1]} and the
 * severity band it falls into.
 *
 * <p>Reports and CLI output are assembled from these records, so the field
 * accessors are part of the output contract.
 */
public final class Assessment {

    private final String code;
    private final String method;
    private final double level;
    private final Severity severity;

    private Assessment(String code, String method, double level, Severity severity) {
        this.code = Objects.requireNonNull(code, "code");
        this.method = Objects.requireNonNull(method, "method");
        this.level = level;
        this.severity = Objects.requireNonNull(severity, "severity");
    }

    /**
     * Factory equivalent of the constructor.
     *
     * @param code stable strategy code, e.g. {@code "baseline"}
     * @param method human description of the estimator
     * @param level level fraction in {@code [0, 1]}
     * @param severity severity band of the level
     * @return a new immutable assessment
     */
    public static Assessment of(String code, String method, double level, Severity severity) {
        return new Assessment(code, method, level, severity);
    }

    public String code() {
        return code;
    }

    public String method() {
        return method;
    }

    public double level() {
        return level;
    }

    public Severity severity() {
        return severity;
    }
}
'''

FILES[f"{SRC}/com/cistern/model/JsonCodec.java"] = r'''package com.cistern.model;

import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Small deterministic JSON writer used by the report module and the CLI.
 *
 * <p>Keys are emitted in insertion order and numbers use a compact decimal
 * form, so two runs over the same data produce byte-identical output. Only
 * the value types listed in {@link #writeValue} are supported; anything else
 * is rejected rather than silently mangled.
 */
public final class JsonCodec {

    private JsonCodec() {
        // utility class
    }

    /**
     * Renders an object whose values are String, Number, Boolean, null,
     * nested {@link Map}s or {@link List}s.
     *
     * @param object ordered map to serialise
     * @return compact JSON text
     */
    public static String writeObject(Map<String, Object> object) {
        StringBuilder out = new StringBuilder();
        out.append('{');
        boolean first = true;
        for (Map.Entry<String, Object> entry : object.entrySet()) {
            if (!first) {
                out.append(',');
            }
            first = false;
            out.append('"').append(escape(entry.getKey())).append("\":");
            writeValue(out, entry.getValue());
        }
        out.append('}');
        return out.toString();
    }

    /** Renders a list of JSON-serialisable values. */
    public static String writeList(List<?> list) {
        StringBuilder out = new StringBuilder();
        out.append('[');
        boolean first = true;
        for (Object value : list) {
            if (!first) {
                out.append(',');
            }
            first = false;
            writeValue(out, value);
        }
        out.append(']');
        return out.toString();
    }

    private static void writeValue(StringBuilder out, Object value) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof String text) {
            out.append('"').append(escape(text)).append('"');
        } else if (value instanceof Double number) {
            out.append(formatNumber(number));
        } else if (value instanceof Integer number) {
            out.append(number);
        } else if (value instanceof Long number) {
            out.append(number);
        } else if (value instanceof Boolean bool) {
            out.append(bool);
        } else if (value instanceof Map<?, ?> nested) {
            out.append(writeObject((Map<String, Object>) (Object) nested));
        } else if (value instanceof List<?> list) {
            out.append(writeList(list));
        } else {
            throw new IllegalArgumentException("cannot encode " + value.getClass().getName());
        }
    }

    /**
     * Compact decimal formatting: integral values lose the trailing
     * {@code ".0"}, and fractionals keep up to six significant decimals with
     * trailing zeros stripped.
     *
     * @param value number to format
     * @return stable, short decimal text
     */
    public static String formatNumber(double value) {
        if (value == Math.rint(value) && Math.abs(value) < 1e15) {
            return String.format(Locale.ROOT, "%.0f", value);
        }
        String fixed = String.format(Locale.ROOT, "%.6f", value);
        fixed = fixed.replaceFirst("0+$", "").replaceFirst("\\.$", "");
        return fixed;
    }

    /** Escapes a string per the JSON specification. */
    public static String escape(String raw) {
        StringBuilder out = new StringBuilder(raw.length() + 8);
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                case '\b' -> out.append("\\b");
                case '\f' -> out.append("\\f");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        return out.toString();
    }
}
'''

FILES[f"{SRC}/com/cistern/model/CsvCodec.java"] = '''package com.cistern.model;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Minimal CSV codec for the pipeline format.
 *
 * <p>Rows are {@code timestamp,value,unit,source}; the unit column accepts
 * either a {@link Units#code() code} or {@link Units#symbol() symbol}, and
 * the source column is optional. Blank lines and lines starting with
 * {@code #} are ignored, which keeps hand-maintained sample files readable.
 * The parser is strict about numeric fields: a malformed row is an error, not
 * a silently dropped sample.
 */
public final class CsvCodec {

    private CsvCodec() {
        // utility class
    }

    /**
     * Parses CSV text into samples.
     *
     * @param text the whole CSV document
     * @return parsed samples in row order
     * @throws IllegalArgumentException on the first malformed row
     */
    public static List<Sample> parseSamples(String text) {
        List<Sample> out = new ArrayList<>();
        for (String raw : text.split("\\\\R")) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String[] parts = line.split(",", -1);
            if (parts.length < 3) {
                throw new IllegalArgumentException("malformed row: " + line);
            }
            long timestamp;
            double value;
            try {
                timestamp = Long.parseLong(parts[0].trim());
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("bad timestamp in row: " + line);
            }
            try {
                value = Double.parseDouble(parts[1].trim());
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException("bad value in row: " + line);
            }
            Optional<Units> unit = Units.parse(parts[2]);
            if (unit.isEmpty()) {
                throw new IllegalArgumentException("bad unit in row: " + line);
            }
            String source = parts.length >= 4 ? parts[3].trim() : "";
            out.add(Sample.of(timestamp, value, unit.get(), source));
        }
        return out;
    }

    /** Serialises samples back into rows, one per sample. */
    public static String writeSamples(List<Sample> samples) {
        StringBuilder out = new StringBuilder();
        for (Sample sample : samples) {
            out.append(sample.timestampMillis()).append(',')
               .append(JsonCodec.formatNumber(sample.value())).append(',')
               .append(sample.unit().code()).append(',')
               .append(sample.source()).append('\\n');
        }
        return out.toString();
    }
}
'''
FILES[f"{SRC}/com/cistern/model/TimeShifter.java"] = '''package com.cistern.model;

/**
 * Time-axis helpers for windows: shifting and interval alignment.
 *
 * <p>Field instruments occasionally capture on a skewed clock. The shifter
 * moves the whole axis by a fixed delta, and {@link #alignTo} floors every
 * timestamp to an interval boundary so windows captured at slightly
 * different moments can be overlaid for comparison.
 */
public final class TimeShifter {

    private TimeShifter() {
        // utility class
    }

    /**
     * Returns a window with every timestamp moved by {@code deltaMillis}.
     *
     * @param window the source window
     * @param deltaMillis signed shift in millis
     * @return a new window with shifted timestamps
     */
    public static SampleWindow shift(SampleWindow window, long deltaMillis) {
        Sample[] shifted = new Sample[window.size()];
        int i = 0;
        for (Sample sample : window.samples()) {
            shifted[i++] = Sample.of(sample.timestampMillis() + deltaMillis,
                    sample.value(), sample.unit(), sample.source());
        }
        return SampleWindow.of(shifted);
    }

    /**
     * Returns a window whose timestamps are floored to boundaries of
     * {@code intervalMillis}.
     *
     * @param window the source window
     * @param intervalMillis alignment interval, positive
     * @return a new window with aligned timestamps
     * @throws IllegalArgumentException when the interval is not positive
     */
    public static SampleWindow alignTo(SampleWindow window, long intervalMillis) {
        if (intervalMillis <= 0) {
            throw new IllegalArgumentException("interval must be positive: " + intervalMillis);
        }
        Sample[] aligned = new Sample[window.size()];
        int i = 0;
        for (Sample sample : window.samples()) {
            long timestamp = sample.timestampMillis();
            long floored = timestamp - Math.floorMod(timestamp, intervalMillis);
            aligned[i++] = Sample.of(floored, sample.value(), sample.unit(), sample.source());
        }
        return SampleWindow.of(aligned);
    }
}
'''

FILES[f"{SRC}/com/cistern/model/OutageCalendar.java"] = '''package com.cistern.model;

import java.util.ArrayList;
import java.util.List;

/**
 * A calendar of known coverage outages for a station.
 *
 * <p>An outage is a half-open interval {@code [startMillis, endMillis)}.
 * Reports consult the calendar to explain why a window is missing samples:
 * the CLI {@code inspect} command prints the fraction of the example window
 * covered by the calendar.
 */
public final class OutageCalendar {

    /**
     * A half-open outage interval.
     *
     * @param startMillis inclusive start of the outage
     * @param endMillis exclusive end of the outage
     */
    public record Interval(long startMillis, long endMillis) {

        public Interval {
            if (endMillis < startMillis) {
                throw new IllegalArgumentException("outage end before start");
            }
        }

        /** Whether the interval covers the given timestamp. */
        public boolean contains(long timestamp) {
            return timestamp >= startMillis && timestamp < endMillis;
        }
    }

    private final List<Interval> intervals;

    public OutageCalendar() {
        this.intervals = new ArrayList<>();
    }

    public OutageCalendar(List<Interval> intervals) {
        this.intervals = new ArrayList<>(intervals);
    }

    /** Adds an interval and returns {@code this} for fluent call sites. */
    public OutageCalendar add(long startMillis, long endMillis) {
        intervals.add(new Interval(startMillis, endMillis));
        return this;
    }

    /** Whether any interval covers the timestamp. */
    public boolean contains(long timestamp) {
        for (Interval interval : intervals) {
            if (interval.contains(timestamp)) {
                return true;
            }
        }
        return false;
    }

    /** Whether any interval overlaps the half-open range. */
    public boolean overlaps(long startMillis, long endMillis) {
        for (Interval interval : intervals) {
            if (interval.startMillis() < endMillis && interval.endMillis() > startMillis) {
                return true;
            }
        }
        return false;
    }

    /** How many samples of the window fall inside a known outage. */
    public long coveredSamples(SampleWindow window) {
        long count = 0;
        for (Sample sample : window.samples()) {
            if (contains(sample.timestampMillis())) {
                count++;
            }
        }
        return count;
    }

    /** Fraction of the window's samples inside an outage, in {@code [0, 1]}. */
    public double coverage(SampleWindow window) {
        if (window.isEmpty()) {
            return 0.0;
        }
        return (double) coveredSamples(window) / window.size();
    }

    /** Defensive copy of the registered intervals in insertion order. */
    public List<Interval> intervals() {
        return new ArrayList<>(intervals);
    }
}
'''

FILES[f"{SRC}/com/cistern/model/WindowMerger.java"] = '''package com.cistern.model;

import java.util.TreeMap;

/**
 * Merges two windows into one chronological window.
 *
 * <p>Samples sharing a timestamp are deduplicated, keeping the sample from the
 * first window, so a freshly re-captured window can be overlaid onto an
 * archived one without double counting a reading.
 */
public final class WindowMerger {

    private WindowMerger() {
        // utility class
    }

    /**
     * Merges two windows by timestamp, preserving chronological order.
     *
     * @param first first window (wins timestamp ties)
     * @param second second window
     * @return a new window with one sample per timestamp
     */
    public static SampleWindow merge(SampleWindow first, SampleWindow second) {
        TreeMap<Long, Sample> byTimestamp = new TreeMap<>();
        for (Sample sample : first.samples()) {
            byTimestamp.putIfAbsent(sample.timestampMillis(), sample);
        }
        for (Sample sample : second.samples()) {
            byTimestamp.putIfAbsent(sample.timestampMillis(), sample);
        }
        return SampleWindow.of(byTimestamp.values().stream().toList());
    }

    /**
     * Number of distinct timestamps across the two windows.
     *
     * @param first first window
     * @param second second window
     * @return the size of the merged window
     */
    public static int distinctCount(SampleWindow first, SampleWindow second) {
        return merge(first, second).size();
    }
}
'''

FILES[f"{SRC}/com/cistern/model/DurationFormat.java"] = '''package com.cistern.model;

import java.util.Locale;

/**
 * Compact human formatting of millisecond durations.
 *
 * <p>The reporting module uses this for window spans and the CLI for sample
 * cadence diagnostics: {@code 0-59s} prints as seconds, minutes and hours are
 * abbreviated, and anything that fits in a day gets hours plus minutes.
 */
public final class DurationFormat {

    private DurationFormat() {
        // utility class
    }

    /**
     * Formats a duration.
     *
     * @param millis duration in millis, may be negative (formatted as-is)
     * @return e.g. {@code "45s"}, {@code "3m 12s"}, {@code "3h 4m"}
     */
    public static String format(long millis) {
        long totalSeconds = millis / 1000L;
        long seconds = totalSeconds % 60L;
        long totalMinutes = totalSeconds / 60L;
        long minutes = totalMinutes % 60L;
        long hours = totalMinutes / 60L;
        if (hours > 0) {
            return String.format(Locale.ROOT, "%dh %dm", hours, minutes);
        }
        if (totalMinutes > 0) {
            return String.format(Locale.ROOT, "%dm %ds", minutes, seconds);
        }
        return seconds + "s";
    }

    /**
     * Formats a duration in seconds.
     *
     * @param seconds duration in seconds
     * @return the {@link #format(long) format} of the milliseconds
     */
    public static String formatSeconds(long seconds) {
        return format(seconds * 1000L);
    }
}
'''

FILES[f"{SRC}/com/cistern/model/Summary.java"] = '''package com.cistern.model;

import java.util.LinkedHashMap;

/**
 * Immutable descriptive summary of a window.
 *
 * <p>{@link #of(SampleWindow)} computes all the headline statistics in one
 * pass over the window and freezes them, so callers - the CLI and stored
 * outputs - share one consistent set of numbers for the same window.
 */
public final class Summary {

    private final int count;
    private final double min;
    private final double max;
    private final double mean;
    private final double standardDeviation;
    private final double range;

    private Summary(int count, double min, double max, double mean,
                    double standardDeviation, double range) {
        this.count = count;
        this.min = min;
        this.max = max;
        this.mean = mean;
        this.standardDeviation = standardDeviation;
        this.range = range;
    }

    /** Computes the summary of a window. */
    public static Summary of(SampleWindow window) {
        return new Summary(window.size(), window.min(), window.max(),
                window.mean(), window.standardDeviation(), window.range());
    }

    public int count() {
        return count;
    }

    public double min() {
        return min;
    }

    public double max() {
        return max;
    }

    public double mean() {
        return mean;
    }

    public double standardDeviation() {
        return standardDeviation;
    }

    public double range() {
        return range;
    }

    public boolean isEmpty() {
        return count == 0;
    }

    /** Ordered map view with stable keys, for the JSON layer. */
    public LinkedHashMap<String, Object> toMap() {
        LinkedHashMap<String, Object> map = new LinkedHashMap<>();
        map.put("count", count);
        map.put("min", min);
        map.put("max", max);
        map.put("mean", mean);
        map.put("stdev", standardDeviation);
        map.put("range", range);
        return map;
    }

    @Override
    public String toString() {
        return "Summary{count=" + count + ", mean=" + mean + "}";
    }
}
'''
