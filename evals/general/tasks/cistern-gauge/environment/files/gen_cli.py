# -*- coding: utf-8 -*-
"""Sources for the cistern-cli module (com.cistern.cli).

Part of the cistern-gauge fixture generator.
"""

SRC = "cistern-cli/src/main/java"

FILES = {}

FILES[f"{SRC}/com/cistern/cli/Command.java"] = '''package com.cistern.cli;

/**
 * One CLI sub-command.
 *
 * <p>Commands are small, stateless and testable directly: the test suite
 * invokes {@link #run(String[], int)} the same way {@link Main} does, so the
 * module needs no packaging step to be covered.
 */
public interface Command {

    /** Command name as typed on the command line. */
    String name();

    /**
     * Runs the command.
     *
     * @param args the full argument vector of the process
     * @param index index of the first argument belonging to this command
     * @return the process exit code (0 success, 1 runtime failure, 2 usage)
     */
    int run(String[] args, int index);

    /** One-line usage string for the help listing. */
    String usage();
}
'''

FILES[f"{SRC}/com/cistern/cli/VersionCommand.java"] = '''package com.cistern.cli;

/**
 * Prints the toolchain version.
 */
public final class VersionCommand implements Command {

    /** Full version banner printed by the {@code version} command. */
    public static final String VERSION =
            "cistern-cli 1.4.2 (cistern-gauge reactor 1.4.2)";

    @Override
    public String name() {
        return "version";
    }

    @Override
    public int run(String[] args, int index) {
        System.out.println(VERSION);
        return 0;
    }

    @Override
    public String usage() {
        return "version";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/ConvertCommand.java"] = '''package com.cistern.cli;

import com.cistern.model.JsonCodec;
import com.cistern.model.Units;
import java.util.Optional;

/**
 * Converts a volume between units: {@code convert <value> <from> <to>}.
 */
public final class ConvertCommand implements Command {

    @Override
    public String name() {
        return "convert";
    }

    @Override
    public int run(String[] args, int index) {
        if (args.length < index + 3) {
            System.out.println("usage: cistern convert <value> <from> <to>");
            return 2;
        }
        double value;
        try {
            value = Double.parseDouble(args[index]);
        } catch (NumberFormatException e) {
            System.out.println("error: value is not a number: " + args[index]);
            return 2;
        }
        Optional<Units> from = Units.parse(args[index + 1]);
        Optional<Units> to = Units.parse(args[index + 2]);
        if (from.isEmpty() || to.isEmpty()) {
            System.out.println("error: unknown unit (from=" + args[index + 1]
                    + ", to=" + args[index + 2] + ")");
            return 2;
        }
        double litres = from.get().toLitres(value);
        System.out.println(JsonCodec.formatNumber(to.get().fromLitres(litres)));
        return 0;
    }

    @Override
    public String usage() {
        return "convert <value> <from> <to>";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/AssessCommand.java"] = '''package com.cistern.cli;

import com.cistern.core.ConfidenceBand;
import com.cistern.model.Assessment;
import com.cistern.model.CsvCodec;
import com.cistern.model.JsonCodec;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import com.cistern.report.ReportPipeline;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Runs one strategy over a CSV of samples and prints the level fraction:
 * {@code assess <strategy> <capacity> <csv-file>}.
 */
public final class AssessCommand implements Command {

    @Override
    public String name() {
        return "assess";
    }

    @Override
    public int run(String[] args, int index) {
        if (args.length < index + 3) {
            System.out.println("usage: cistern assess <strategy> <capacity> <csv-file>");
            return 2;
        }
        String code = args[index];
        double capacity;
        try {
            capacity = Double.parseDouble(args[index + 1]);
        } catch (NumberFormatException e) {
            System.out.println("error: capacity is not a number: " + args[index + 1]);
            return 2;
        }
        Path csv = Path.of(args[index + 2]);
        if (!Files.isReadable(csv)) {
            System.out.println("error: cannot read " + csv);
            return 2;
        }
        try {
            String text = Files.readString(csv);
            SampleWindow window = SampleWindow.of(CsvCodec.parseSamples(text));
            Threshold threshold = Threshold.standard(capacity);
            ReportPipeline pipeline = new ReportPipeline();
            Assessment assessment = pipeline.assess(code, window, threshold);
            ConfidenceBand band = ConfidenceBand.of(pipeline.assessorFor(code), window, threshold);
            System.out.println(assessment.code() + " " + JsonCodec.formatNumber(assessment.level())
                    + " " + assessment.severity().code() + " " + assessment.method()
                    + " [" + JsonCodec.formatNumber(band.lower()) + ".."
                    + JsonCodec.formatNumber(band.upper()) + "]");
            return 0;
        } catch (Exception e) {
            System.out.println("error: " + e.getMessage());
            return 1;
        }
    }

    @Override
    public String usage() {
        return "assess <strategy> <capacity> <csv-file>";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/ReportCommand.java"] = '''package com.cistern.cli;

import com.cistern.model.CsvCodec;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import com.cistern.report.ReportPipeline;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Renders a JSON report for one strategy over a CSV of samples:
 * {@code report <strategy> <capacity> <csv-file>}.
 */
public final class ReportCommand implements Command {

    @Override
    public String name() {
        return "report";
    }

    @Override
    public int run(String[] args, int index) {
        if (args.length < index + 3) {
            System.out.println("usage: cistern report <strategy> <capacity> <csv-file>");
            return 2;
        }
        String code = args[index];
        double capacity;
        try {
            capacity = Double.parseDouble(args[index + 1]);
        } catch (NumberFormatException e) {
            System.out.println("error: capacity is not a number: " + args[index + 1]);
            return 2;
        }
        Path csv = Path.of(args[index + 2]);
        if (!Files.isReadable(csv)) {
            System.out.println("error: cannot read " + csv);
            return 2;
        }
        try {
            String text = Files.readString(csv);
            SampleWindow window = SampleWindow.of(CsvCodec.parseSamples(text));
            Threshold threshold = Threshold.standard(capacity);
            System.out.println(new ReportPipeline().renderJson(code, window, threshold));
            return 0;
        } catch (Exception e) {
            System.out.println("error: " + e.getMessage());
            return 1;
        }
    }

    @Override
    public String usage() {
        return "report <strategy> <capacity> <csv-file>";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/InspectCommand.java"] = '''package com.cistern.cli;

import com.cistern.core.AssessorRegistry;
import com.cistern.core.BaselineTables;
import com.cistern.core.Calibration;
import com.cistern.model.CsvCodec;
import com.cistern.model.JsonCodec;
import com.cistern.model.OutageCalendar;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;

/**
 * Prints the registered strategies, the calibration tables and a short
 * calibration check of the shipped example window: {@code inspect}.
 */
public final class InspectCommand implements Command {

    private static final Path EXAMPLE = Path.of("conf/example-samples.csv");

    @Override
    public String name() {
        return "inspect";
    }

    @Override
    public int run(String[] args, int index) {
        Table strategies = Table.withColumns("code", "estimator");
        for (String code : AssessorRegistry.codes()) {
            strategies.addRow(List.of(code, AssessorRegistry.byCode(code).describe()));
        }
        System.out.println("registered strategies:");
        System.out.print(strategies.render());
        System.out.println("hourly fill fraction:");
        for (var entry : BaselineTables.hourlyFillFraction().entrySet()) {
            System.out.println("  " + String.format(Locale.ROOT, "%02d:00 %s",
                    entry.getKey(), JsonCodec.formatNumber(entry.getValue())));
        }
        OutageCalendar calendar = new OutageCalendar();
        calendar.add(2_900L, 8_300L)
                .add(38_900L, 44_100L);
        System.out.println("outage calendar: " + calendar.intervals().size() + " intervals");
        try {
            List<Sample> samples = CsvCodec.parseSamples(Files.readString(EXAMPLE));
            SampleWindow window = SampleWindow.of(samples);
            System.out.println("example outage coverage: "
                    + JsonCodec.formatNumber(calendar.coverage(window)));
            System.out.println("example calibration residual: "
                    + JsonCodec.formatNumber(new Calibration(1000.0).meanResidual(window)));
        } catch (Exception e) {
            System.out.println("example window: none found (" + e.getMessage() + ")");
        }
        return 0;
    }

    @Override
    public String usage() {
        return "inspect";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/HistoryCommand.java"] = '''package com.cistern.cli;

import com.cistern.model.CsvCodec;
import com.cistern.model.JsonCodec;
import com.cistern.model.Sample;
import com.cistern.model.SampleWindow;
import com.cistern.model.Summary;
import com.cistern.model.Threshold;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Lists a CSV of readings with level and severity per row:
 * {@code history <capacity> <csv-file>}.
 */
public final class HistoryCommand implements Command {

    @Override
    public String name() {
        return "history";
    }

    @Override
    public int run(String[] args, int index) {
        if (args.length < index + 2) {
            System.out.println("usage: cistern history <capacity> <csv-file>");
            return 2;
        }
        double capacity;
        try {
            capacity = Double.parseDouble(args[index]);
        } catch (NumberFormatException e) {
            System.out.println("error: capacity is not a number: " + args[index]);
            return 2;
        }
        Path csv = Path.of(args[index + 1]);
        if (!Files.isReadable(csv)) {
            System.out.println("error: cannot read " + csv);
            return 2;
        }
        try {
            String text = Files.readString(csv);
            Threshold threshold = Threshold.standard(capacity);
            Summary summary = Summary.of(SampleWindow.of(CsvCodec.parseSamples(text)));
            System.out.println("window summary: count=" + summary.count()
                    + " mean=" + JsonCodec.formatNumber(summary.mean()));
            for (Sample sample : CsvCodec.parseSamples(text)) {
                double level = threshold.levelOf(sample.valueLitres());
                System.out.println(sample.timestampMillis() + " "
                        + JsonCodec.formatNumber(level) + " "
                        + threshold.severityOfFraction(level).code());
            }
            return 0;
        } catch (Exception e) {
            System.out.println("error: " + e.getMessage());
            return 1;
        }
    }

    @Override
    public String usage() {
        return "history <capacity> <csv-file>";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/CompareCommand.java"] = '''package com.cistern.cli;

import com.cistern.core.AssessmentHistory;
import com.cistern.core.AssessorRegistry;
import com.cistern.model.CsvCodec;
import com.cistern.model.JsonCodec;
import com.cistern.model.SampleWindow;
import com.cistern.model.Threshold;
import com.cistern.model.Trend;
import com.cistern.model.WindowMerger;
import com.cistern.report.Report;
import com.cistern.report.ReportBuilder;
import com.cistern.report.ReportComparator;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Compares two windows: per-strategy level before and after, plus the overall
 * trend: {@code compare <capacity> <csv-before> <csv-after>}.
 */
public final class CompareCommand implements Command {

    @Override
    public String name() {
        return "compare";
    }

    @Override
    public int run(String[] args, int index) {
        if (args.length < index + 3) {
            System.out.println("usage: cistern compare <capacity> <csv-before> <csv-after>");
            return 2;
        }
        double capacity;
        try {
            capacity = Double.parseDouble(args[index]);
        } catch (NumberFormatException e) {
            System.out.println("error: capacity is not a number: " + args[index]);
            return 2;
        }
        try {
            SampleWindow before = SampleWindow.of(CsvCodec.parseSamples(
                    Files.readString(Path.of(args[index + 1]))));
            SampleWindow after = SampleWindow.of(CsvCodec.parseSamples(
                    Files.readString(Path.of(args[index + 2]))));
            Threshold threshold = Threshold.standard(capacity);
            for (String code : AssessorRegistry.codes()) {
                double fromLevel = AssessorRegistry.byCode(code).assess(before, threshold);
                double toLevel = AssessorRegistry.byCode(code).assess(after, threshold);
                System.out.println(code + " " + JsonCodec.formatNumber(fromLevel)
                        + " -> " + JsonCodec.formatNumber(toLevel) + " "
                        + Trend.between(fromLevel, toLevel).label());
            }
            SampleWindow merged = WindowMerger.merge(before, after);
            System.out.println("merged window: " + merged.size() + " samples ("
                    + (before.size() + after.size()) + " input)");
            AssessmentHistory history = new AssessmentHistory(8);
            for (String code : AssessorRegistry.codes()) {
                history.record(code, AssessorRegistry.byCode(code).assess(after, threshold));
            }
            System.out.println("assessment history: " + history.summary());
            Report beforeReport = new ReportBuilder().buildSingle(
                    com.cistern.model.ReportHeader.now("compare"), before, threshold, "baseline");
            Report afterReport = new ReportBuilder().buildSingle(
                    com.cistern.model.ReportHeader.now("compare"), after, threshold, "baseline");
            System.out.println("baseline delta: " + ReportComparator.describe(beforeReport, afterReport));
            return 0;
        } catch (Exception e) {
            System.out.println("error: " + e.getMessage());
            return 1;
        }
    }

    @Override
    public String usage() {
        return "compare <capacity> <csv-before> <csv-after>";
    }
}
'''

FILES[f"{SRC}/com/cistern/cli/Main.java"] = '''package com.cistern.cli;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Console entry point of the cistern-gauge tooling.
 *
 * <p>Dispatches to the registered sub-commands. Tests invoke
 * {@link #run(String[])} directly so the reactor suite can exercise the whole
 * CLI without a packaging step.
 */
public final class Main {

    private static final Map<String, Command> COMMANDS = commands();

    private Main() {
        // utility class
    }

    private static Map<String, Command> commands() {
        LinkedHashMap<String, Command> commands = new LinkedHashMap<>();
        register(commands, new AssessCommand());
        register(commands, new ReportCommand());
        register(commands, new InspectCommand());
        register(commands, new ConvertCommand());
        register(commands, new HistoryCommand());
        register(commands, new CompareCommand());
        register(commands, new VersionCommand());
        return commands;
    }

    private static void register(Map<String, Command> commands, Command command) {
        commands.put(command.name(), command);
    }

    /** JVM entry point; {@code args} excludes the program name. */
    public static void main(String[] args) {
        System.exit(run(args));
    }

    /**
     * Runs the CLI and returns the process exit code.
     *
     * @param args full argument vector excluding the program name
     * @return 0 success, 2 usage error; commands may return 1 for runtime errors
     */
    public static int run(String[] args) {
        if (args.length == 0) {
            System.out.println("usage: cistern <command> ...");
            for (Command command : COMMANDS.values()) {
                System.out.println("  " + command.usage());
            }
            return 0;
        }
        Command command = COMMANDS.get(args[0]);
        if (command == null) {
            System.out.println("unknown command: " + args[0]);
            return 2;
        }
        return command.run(args, 1);
    }
}
'''
FILES[f"{SRC}/com/cistern/cli/Table.java"] = r'''package com.cistern.cli;

import java.util.ArrayList;
import java.util.List;

/**
 * Minimal aligned-column table for CLI output.
 *
 * <p>Columns are sized to the widest cell, cells within a column are padded
 * to the same width, and columns are separated by two spaces. The render is
 * deterministic, which keeps command output diffable in logs.
 */
public final class Table {

    private final List<String> headers;
    private final List<List<String>> rows = new ArrayList<>();
    private final int[] widths;

    private Table(List<String> headers) {
        this.headers = List.copyOf(headers);
        this.widths = new int[headers.size()];
        for (int i = 0; i < headers.size(); i++) {
            widths[i] = headers.get(i).length();
        }
    }

    /** Opens a table with the given column headers. */
    public static Table withColumns(String... headers) {
        return new Table(List.of(headers));
    }

    /** Adds a row; every row must have exactly one cell per column. */
    public Table addRow(List<String> cells) {
        if (cells.size() != widths.length) {
            throw new IllegalArgumentException("row has " + cells.size()
                    + " cells, expected " + widths.length);
        }
        rows.add(List.copyOf(cells));
        for (int i = 0; i < widths.length; i++) {
            widths[i] = Math.max(widths[i], cells.get(i).length());
        }
        return this;
    }

    /** Renders header and rows as an aligned block ending with a newline. */
    public String render() {
        StringBuilder out = new StringBuilder();
        appendRow(out, headers);
        for (List<String> row : rows) {
            appendRow(out, row);
        }
        return out.toString();
    }

    private void appendRow(StringBuilder out, List<String> cells) {
        for (int i = 0; i < cells.size(); i++) {
            if (i > 0) {
                out.append("  ");
            }
            out.append(String.format("%-" + widths[i] + "s", cells.get(i)));
        }
        out.append('\n');
    }
}
'''
