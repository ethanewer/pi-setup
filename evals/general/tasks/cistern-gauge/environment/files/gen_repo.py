# -*- coding: utf-8 -*-
"""Generator for the cistern-gauge reactor repository.

Builds the Maven multi-module Java 21 repository at the target directory and
commits it with an incremental git history (14 commits). The Dockerfile runs
this once at image-build time; the resulting repository ships with a green
JUnit 5 suite and a fully populated local Maven cache.

While the generator runs, the gen_*.py files sit next to the target (the
image copies this whole directory), so they delete themselves right after
import - Python has already loaded them into memory - and the repository is
created without ever tracking them.

Usage: python3 gen_repo.py [target-dir]    # default: /app
"""

import shutil
import subprocess
import sys
from pathlib import Path

import gen_model
import gen_core
import gen_report
import gen_cli
import gen_tests

# --- remove the generator scripts themselves before any git operation ---
_here = Path(__file__).resolve().parent
for _name in ("gen_repo.py", "gen_model.py", "gen_core.py", "gen_report.py",
              "gen_cli.py", "gen_tests.py"):
    try:
        (_here / _name).unlink()
    except FileNotFoundError:
        pass

TARGET = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/app")


def subset(files, *needles):
    if not needles:
        return dict(files)
    return {p: files[p] for p in files if any(n in p for n in needles)}


def complement(files, taken):
    return {p: files[p] for p in files if p not in taken}


def test_files(files, module_name):
    return {p: files[p] for p in files if p.startswith(module_name + "/src/test")}


def git(*args, check=True):
    subprocess.run(["git", *args], cwd=str(TARGET), check=check,
                   capture_output=True, text=True)


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


POMS = {
    "pom.xml": """<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>

  <groupId>io.cistern</groupId>
  <artifactId>cistern-reactor</artifactId>
  <version>1.4.2</version>
  <packaging>pom</packaging>

  <name>cistern-gauge reactor</name>
  <description>Multi-module Java 21 stack for reservoir level telemetry:
    domain model, level assessment strategies, reporting and CLI.</description>

  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <maven.compiler.release>21</maven.compiler.release>
    <maven.compiler.plugin.version>3.13.0</maven.compiler.plugin.version>
    <maven.surefire.plugin.version>3.2.5</maven.surefire.plugin.version>
    <junit.jupiter.version>5.11.4</junit.jupiter.version>
  </properties>

  <modules>
    <module>cistern-model</module>
    <module>cistern-core</module>
    <module>cistern-report</module>
    <module>cistern-cli</module>
  </modules>

  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>${junit.jupiter.version}</version>
      </dependency>
    </dependencies>
  </dependencyManagement>

  <build>
    <pluginManagement>
      <plugins>
        <plugin>
          <groupId>org.apache.maven.plugins</groupId>
          <artifactId>maven-compiler-plugin</artifactId>
          <version>${maven.compiler.plugin.version}</version>
          <configuration>
            <release>21</release>
          </configuration>
        </plugin>
        <plugin>
          <groupId>org.apache.maven.plugins</groupId>
          <artifactId>maven-surefire-plugin</artifactId>
          <version>${maven.surefire.plugin.version}</version>
        </plugin>
      </plugins>
    </pluginManagement>
  </build>
</project>
""",
    "cistern-model/pom.xml": """<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>io.cistern</groupId>
    <artifactId>cistern-reactor</artifactId>
    <version>1.4.2</version>
    <relativePath>../pom.xml</relativePath>
  </parent>
  <artifactId>cistern-model</artifactId>
  <name>cistern-model</name>
  <description>Domain model shared by the whole stack: units, samples,
    windows, thresholds, severities and the JSON/CSV codecs.</description>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
""",
    "cistern-core/pom.xml": """<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>io.cistern</groupId>
    <artifactId>cistern-reactor</artifactId>
    <version>1.4.2</version>
    <relativePath>../pom.xml</relativePath>
  </parent>
  <artifactId>cistern-core</artifactId>
  <name>cistern-core</name>
  <description>Level assessment strategies behind the LevelAssessor contract,
    the named registry and the assessment engine.</description>
  <dependencies>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-model</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
""",
    "cistern-report/pom.xml": """<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>io.cistern</groupId>
    <artifactId>cistern-reactor</artifactId>
    <version>1.4.2</version>
    <relativePath>../pom.xml</relativePath>
  </parent>
  <artifactId>cistern-report</artifactId>
  <name>cistern-report</name>
  <description>Structured reports assembled through the LevelAssessor
    interface, with deterministic text and JSON renderers.</description>
  <dependencies>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-core</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-model</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
""",
    "cistern-cli/pom.xml": """<?xml version="1.0" encoding="UTF-8"?>
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>io.cistern</groupId>
    <artifactId>cistern-reactor</artifactId>
    <version>1.4.2</version>
    <relativePath>../pom.xml</relativePath>
  </parent>
  <artifactId>cistern-cli</artifactId>
  <name>cistern-cli</name>
  <description>Console entry point over the report pipeline: assess, report,
    inspect, convert, history and compare sub-commands.</description>
  <dependencies>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-report</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-core</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>io.cistern</groupId>
      <artifactId>cistern-model</artifactId>
      <version>1.4.2</version>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
""",
}

ROOT_FILES = {
    ".gitignore": "target/\n*.log\n*.class\n*.pyc\n__pycache__/\n.idea/\n*.iml\n.vscode/\n.DS_Store\n",
    "README.md": """# cistern-gauge

Multi-module Java 21 stack for reservoir level telemetry. The reactor
assembles four modules behind a single `mvn verify`:

| module | role |
|---|---|
| `cistern-model` | units, samples, windows, thresholds, severities, JSON/CSV codecs |
| `cistern-core`  | level strategies behind the `LevelAssessor` contract, the named registry, the engine |
| `cistern-report`| structured reports and deterministic text/JSON renderers |
| `cistern-cli`   | `assess`, `report`, `inspect`, `convert`, `history`, `compare`, `version` |

## Build

```bash
mvn -o -q -B verify
```

The reactor is configured for offline builds: every dependency and plugin is
already present in the local Maven cache, so the build works with no network.

## Level strategies

Strategies are resolved by stable code through `AssessorRegistry`; unknown
codes degrade to the default baseline strategy.

| code | estimator |
|---|---|
| `baseline`  | central tendency of the window vs capacity (arithmetic mean) |
| `peak`      | maximum of the window |
| `trough`    | minimum of the window |
| `drift`     | range of the window |
| `stability` | inverse deviation of the window |
| `surge`     | recent quarter vs whole window mean |

## CLI examples

```bash
$ cistern inspect
registered strategies:
  baseline -> Baseline level estimate (arithmetic mean of window)
  ...

$ cistern assess peak 1000 conf/example-samples.csv
peak 0.9 nominal Peak level estimate (maximum of window)

$ cistern report baseline 1000 conf/example-samples.csv
{"header":{...},"window":{...},"measures":{"baseline":{"level":0.45,...}},"trend":"falling"}
```

See `docs/ARCHITECTURE.md` and `docs/OUTPUT_FORMAT.md` for details.
""",
    "CHANGELOG.md": """# Changelog

## 1.4.2 - 2025-02-18

- report: deterministic number formatting in the JSON renderer
- cli: history command prints severity per row

## 1.4.1 - 2025-02-04

- core: registry falls back to the baseline strategy for unknown codes
- report: pipeline exposes the structured map view

## 1.4.0 - 2025-01-21

- initial reactor: model, core, report and cli modules with the six
  level strategies and the green JUnit 5 suite
""",
    "docs/ARCHITECTURE.md": """# Architecture

The reactor is a layered stack. Dependencies flow strictly downwards:
`cistern-cli -> cistern-report -> cistern-core -> cistern-model`.

## The strategy boundary

`cistern-core` exposes the `LevelAssessor` interface. Strategies are pure:
`assess(Window, Threshold)` returns a level fraction in `[0, 1]` and never
mutates the window. `AssessorRegistry` is the only place codes map to
implementations, so configuration stays stable when implementations change.

`cistern-report` is a consumer of the interface, never of a concrete
strategy: the pipeline resolves a code through the registry and talks to the
result through `LevelAssessor` only. That is what allows the core module to
change an estimator without the reporting module changing at all.

## The assessment engine

`AssessmentEngine.evaluate` resolves the strategy, runs it and decorates the
level with its severity band (`Threshold.severityOfFraction`). Severity bands:
`[0, warn) nominal`, `[warn, alert) warn`, `[alert, 1) alert`, `1+ critical`.

## Test strategy

Every module ships JUnit 5 coverage. The reactor suite runs with
`mvn -o -q -B verify`; surefire fails the build on any failing test.
""",
    "docs/OUTPUT_FORMAT.md": """# Output format

The JSON report produced by `report` and `ReportPipeline.renderJson` is a
single-line object with stable key order:

```json
{"header":{"station":"pipeline","report_id":"...","generated_at":...,
  "generator":"cistern-report/1.4.2"},
 "window":{"samples":3,"min":100.0,"max":800.0,"mean":433.3},
 "measures":{"baseline":{"level":0.45,"severity":"nominal",
   "method":"Baseline level estimate (arithmetic mean of window)"}},
 "trend":"falling"}
```

- `header.station` is the station id supplied by the caller.
- `window.mean` is the plain arithmetic mean of the window - a model-level
  statistic, unaffected by any strategy.
- `measures.<code>.level` is the strategy's level fraction of capacity.
- `measures.<code>.method` is the strategy's human estimator description.
- Numbers use the compact form: integral values without a decimal point,
  fractionals with up to six decimals and trailing zeros stripped.

## CSV input format

`timestamp,value,unit[,source]` - unit is a `Units` code or symbol. Blank
lines and `#` comments are ignored; malformed rows are errors.
""",
    "conf/example-samples.csv": """# example capture window for site north-01
1000,450,litres,probe-a
2000,480,litres,probe-a
3000,120,gal-uk,probe-b
4000,900,litres,probe-a
""",
}

def build_commits():
    """Compute the ordered commit plan from the CURRENT module sources, so
    sources appended to a generator module are always captured."""
    model_a = subset(gen_model.FILES, "Sample.java", "Units.java", "LevelMath.java")
    model_b = complement(gen_model.FILES, model_a)
    core_interface = subset(gen_core.FILES, "LevelAssessor.java")
    core_strategies = subset(gen_core.FILES,
                             "BaselineAssessor.java", "PeakAssessor.java",
                             "TroughAssessor.java", "DriftAssessor.java",
                             "StabilityAssessor.java", "SurgeAssessor.java",
                             "BaselineTables.java")
    core_engine = complement(gen_core.FILES, core_interface | core_strategies)
    report_base = complement(gen_report.FILES, subset(gen_report.FILES, "ReportPipeline.java"))
    report_pipeline = subset(gen_report.FILES, "ReportPipeline.java")
    root_extra = {k: ROOT_FILES[k] for k in ("docs/ARCHITECTURE.md", "docs/OUTPUT_FORMAT.md")}
    return [
        ("chore: scaffold reactor skeleton and module layout",
         {**POMS, **{k: ROOT_FILES[k] for k in (".gitignore", "README.md")}}),
        ("docs: architecture and output format notes", root_extra),
        ("conf: example capture window",
         {"conf/example-samples.csv": ROOT_FILES["conf/example-samples.csv"]}),
        ("feat(model): volume units, samples and value objects", model_a),
        ("feat(model): windows, thresholds, severities and codecs", model_b),
        ("feat(core): level assessor contract", core_interface),
        ("feat(core): baseline, edge and stability strategies", core_strategies),
        ("feat(core): registry, engine, calibration and history", core_engine),
        ("feat(report): report model and deterministic renderers", report_base),
        ("feat(report): pipeline resolving strategies by code", report_pipeline),
        ("feat(cli): command dispatcher and sub-commands", dict(gen_cli.FILES)),
        ("test(model): domain and codec coverage", test_files(gen_tests.FILES, "cistern-model")),
        ("test(core): assessor and engine coverage", test_files(gen_tests.FILES, "cistern-core")),
        ("test(report): format and renderer coverage", test_files(gen_tests.FILES, "cistern-report")),
        ("test(cli): smoke coverage", test_files(gen_tests.FILES, "cistern-cli")),
    ]


def main() -> None:
    target = TARGET.resolve()
    if target.exists():
        shutil.rmtree(str(target))
    target.mkdir(parents=True, exist_ok=True)
    git("init", "-q", "-b", "main")
    git("config", "user.email", "build@cistern.example")
    git("config", "user.name", "Cistern Build")
    git("config", "commit.gpgsign", "false")

    for number, (message, files) in enumerate(build_commits(), start=1):
        if files:
            for rel, content in files.items():
                write(target / rel, content)
            git("add", "-A")
            git("commit", "-q", "-m", f"[{number:02d}] {message}")

    status = subprocess.run(["git", "status", "--porcelain"],
                            cwd=str(target), capture_output=True, text=True)
    if status.stdout.strip():
        raise SystemExit("generator left a dirty tree: " + status.stdout)

    log = subprocess.run(["git", "log", "--oneline"], cwd=str(target),
                         capture_output=True, text=True)
    print("generated reactor at", target)
    print(log.stdout)


if __name__ == "__main__":
    main()