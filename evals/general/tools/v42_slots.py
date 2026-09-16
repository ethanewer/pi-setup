#!/usr/bin/env python3
"""Task slots for the v4.2 upstream-clone family.

Closes the alignment gap measured against Terminal-Bench: TB2.1 puts an agent
inside a real upstream repository in 42 of its 241 tasks (17%), cloning 35 real
GitHub/GitLab projects, and this suite did it in none of its first 837. The
constraint from the operator is that we may not clone any repository TB2.1 also
uses, so every repo below is a substitute of similar domain and scope, verified
reachable and shallow-cloned and measured before this file was written.

Each entry carries the probe measurement so an author does not have to rediscover
whether the repo is viable: shallow-clone MB, file count, source LOC, and the
build systems present at the top two directory levels.

Refs are the ones resolved by `git ls-remote` on 2026-09-10. An author must
re-resolve the full 40-hex commit for whatever ref it pins and assert it in the
Dockerfile, because tools/check_upstream_disjointness.py requires a pin and a tag
alone can be force-moved upstream.
"""
import json, os, sys
from collections import Counter

EVAL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (name, shape, category, difficulty, repo, ref, probe, brief)
SLOTS = [
    ("clinker-quay", "swe-bench-python", "debugging", "hard",
     "sympy/sympy", "1.14.0", "22MB 2033 files 759,918 LOC pyproject+setup+Makefile",
     "The SWE-bench shape, which is TB2.1's most valuable one and which this suite has never had. Clone sympy pinned, apply ONE small authored patch at build time that introduces a genuine regression in a submodule, and have the agent localise and fix it without being told where it is. The instruction gives a failing behaviour and a reproducer, not a file. Deliverable: the repaired tree plus /app/diagnosis.md naming the module and the cause. Verifier runs sympy's OWN targeted tests for that submodule plus 3 hidden reproducer scripts that exercise the same code path from different inputs, and asserts the rest of the submodule's suite still passes. Do not run the whole sympy suite at 1 CPU; pick a targeted selection and state it in the instruction."),
    ("clinker-mast", "library-feature", "programming", "medium",
     "encode/httpx", "0.28.1", "5MB 125 files 17,751 LOC pyproject",
     "Add a feature to a real, well-tested Python library. Clone httpx pinned, editable-install it, and require a small documented feature that does not exist at that version (for example a retry-transport wrapper or a new event-hook point) implemented in the library's own idiom with its own style. Verifier runs httpx's own relevant test module, then 3 hidden test files that exercise the new feature including its edge cases and its interaction with the existing transport stack, and asserts no existing public API changed signature."),
    ("corbel-weir", "packaging-release", "programming", "medium",
     "pallets/click", "8.5.0", "2MB 166 files 28,588 LOC pyproject",
     "Release engineering against a real project. Clone click pinned and require the agent to produce a correct sdist and wheel from the checkout, fix a deliberate defect seeded in the packaging metadata at build time, and prove the built artifact installs and imports in a clean venv with the right version and entry points. Verifier installs the agent's wheel into a fresh venv and asserts metadata, entry points and 3 hidden behavioural checks against the installed package, not the source tree."),
    ("corbel-stave", "webframework-bugfix", "debugging", "hard",
     "falconry/falcon", "4.3.1", "4MB 428 files 62,287 LOC pyproject+setup+Makefile",
     "Fix a real routing bug in a real micro web framework, standing in for TB2.1's bottlepy/bottle and pallets/flask tasks. Clone falcon pinned, seed one regression in URL template matching or middleware ordering at build time, and require a fix that keeps falcon's own suite green. Verifier runs falcon's relevant test modules and drives a live WSGI app the agent exposes, across 3 hidden route tables including ambiguous templates and a middleware-ordering case."),
    ("derrick-tarn", "extractor-offline", "web", "hard",
     "mikf/gallery-dl", "v1.32.11", "4MB 763 files 128,621 LOC pyproject+setup+Makefile",
     "Stands in for TB2.1's yt-dlp/yt-dlp task. Clone gallery-dl pinned and require a NEW extractor for a fictional site, exercised entirely against a local mock HTTP server the fixture ships and the verifier starts, because there is no external network at trial time. This is the important part: a task that needs the real internet at trial time cannot work here. Verifier starts the mock server on a loopback port, runs the agent's extractor through gallery-dl's own CLI against 3 hidden mock site fixtures, and asserts downloaded file bytes, naming and the extractor's metadata output."),
    ("ferrule-keel", "compiler-from-source", "programming", "hard",
     "TinyCC/tinycc", "release_0_9_27", "3MB 399 files 91,277 LOC Makefile+configure",
     "Build a real C compiler from source, standing in for TB2.1's gcc-mirror/gcc and AbsInt/CompCert tasks at a scope that finishes at 1 CPU. Clone tinycc pinned, build it with its own configure/make, and use the resulting tcc to compile and run a set of C programs including one with a deliberate construct tcc handles differently from gcc. Verifier runs the agent-built tcc binary on 3 hidden C programs, compares behaviour against the system gcc where they must agree, and asserts the documented difference where they must not."),
    ("ferrule-berth", "sat-solver", "programming", "hard",
     "arminbiere/cadical", "c60730422e758ef1cebe7aeddf2dda31c996bf04", "2MB 355 files 29,727 LOC configure+make",
     "Build and drive a real SAT solver, standing in for TB2.1's stp/stp and florentavellaneda/evalmaxsat tasks. Clone cadical at the pinned SHA, build it, and require the agent to use it correctly on DIMACS CNF instances including unsatisfiable ones, incremental assumptions, and a proof trail the agent must check. Verifier runs the agent-built binary on 3 hidden CNF fixtures asserting the verdict, the model actually satisfies the clauses, and the emitted proof is accepted by the project's own proof checker."),
    ("pawl-bell", "chess-engine-build", "programming", "medium",
     "official-stockfish/Stockfish", "59aae690f91d6f69aac194f447d84b4a2c3be778", "1MB 119 files 27,557 LOC Makefile",
     "Build a real C++ engine and drive its protocol, standing in for TB2.1's LeelaChessZero/lc0 task. Clone Stockfish at the pinned SHA, build with make (single-threaded build is fine), and require the agent to drive the UCI protocol: position setup, search to a depth, and reading back the best move and score. Verifier runs the agent-built binary against 3 hidden FEN positions with known best moves at a shallow fixed depth so the assertion is deterministic, and asserts the UCI transcript structure."),
    ("hasp-plumb", "redis-build-operate", "system_administration", "hard",
     "redis/redis", "8.10.1", "1MB shallow 181 files 18,591 LOC Makefile",
     "Build a real server from source and operate it, which no task in this suite has done with an upstream C project. Clone redis at the pinned tag, build with make at 1 CPU, and require the agent to produce a working server config, start it from a deliverable script, and demonstrate a specific persistence and eviction behaviour. Verifier starts the agent's server on a loopback port, drives it with redis-cli across 3 hidden workload fixtures, and asserts keyspace contents, the RDB/AOF artifact on disk, and the configured eviction policy actually evicting under a memory cap."),
    ("ingot-flood", "legacy-c-modernise", "debugging", "hard",
     "id-Software/DOOM", "a77dfb96cb91780ca334d0d4cfd86957558007e0", "1MB 165 files 56,666 LOC Makefile",
     "Modernise a real legacy C codebase, standing in for TB2.1's ozkl/doomgeneric task using the original id-Software release rather than a port. Clone at the pinned SHA and require the agent to get the linuxdoom source to compile against a modern glibc and gcc, fixing the real errors rather than stubbing them, then run a headless non-interactive path far enough to prove the binary works. Verifier compiles from the agent's repaired tree in a clean container and asserts the produced binary runs a fixed non-interactive demo and emits the expected state, across 2 hidden build configurations with different optimization and warning flags."),
    ("jerkin-cleat", "single-header-libs", "programming", "medium",
     "nothings/stb", "2c980bb59875b0d32144a71867fbdebb2f77cd20", "4MB 431 files 108,517 LOC Makefile",
     "Stands in for TB2.1's lvandeve/lodepng task. Clone stb at the pinned SHA and require the agent to write a real image pipeline against stb_image and stb_image_write: decode a set of formats, apply a documented transform, re-encode, and handle the failure modes the headers document. Verifier compiles the agent's program and runs it on 3 hidden image fixtures asserting pixel-exact output, byte-level format conformance and correct behaviour on deliberately corrupt inputs."),
    ("kedge-lattice", "meson-c-library", "programming", "hard",
     "libvips/libvips", "v8.18.6", "34MB 857 files 302,775 LOC meson",
     "Build a real C image library with meson/ninja, standing in for TB2.1's opencv/opencv task at a scope that finishes at 1 CPU. Clone libvips pinned, install its build dependencies from apt, build it, and require the agent to use the built vips CLI and its C API on image fixtures. Verifier runs the agent-built vips binary across 3 hidden image operations asserting pixel checksums and metadata, and links one hidden C program against the agent-built library to prove the install is usable and not just present."),
    ("reeve-gate", "autotools-privilege", "system_administration", "hard",
     "shadow-maint/shadow", "v4.11.1", "39MB 10,599 files 50,194 LOC configure.ac+Makefile.am",
     "Build a real autotools C suite that manages accounts, standing in for TB2.1's sudo-project/sudo task. Clone shadow pinned, run autoreconf/configure/make, install into a prefix, and require the agent to use the built useradd/usermod/passwd binaries to achieve a specific account and privilege state. Verifier inspects /etc/passwd, /etc/shadow, /etc/group and the ownership and mode bits on a set of paths across 3 hidden scenario fixtures, asserting the exact end state and that the agent used its own built binaries rather than the distro's."),
    ("mizzen-summit", "large-jvm-module", "programming", "hard",
     "apache/kafka", "4.3.1", "58MB shallow 7,232 files 1,619,365 LOC gradle",
     "Navigate and build inside a very large real JVM codebase, standing in for TB2.1's apache/flink and apache/spark tasks. Clone kafka pinned, warm the Gradle cache at build time so the trial runs offline, and require a change scoped to ONE module plus running that module's targeted test class. The point is the scale: the agent must find the right module in 7,232 files without being told. Verifier runs the module's targeted tests and 2 hidden test classes that exercise the changed behaviour, and asserts no other module's source changed."),
    ("nock-trestle", "large-jvm-maven", "programming", "hard",
     "trinodb/trino", "pinned SHA (no usable release tags; resolve at authoring time)", "58MB shallow 7,056 files 963,822 LOC maven",
     "The Maven counterpart to the kafka slot, and the second large-JVM navigation task. Trino pushes no numeric release tags, so pin a full commit SHA. Warm the Maven repository at build time into a path the trial reuses with -o, and scope the work to ONE plugin module. If a full mvn build of even one module proves intractable at 1 CPU within a generous build timeout, keep the same repository and convert the task to compiling just the changed sources with javac against a pre-built classpath captured at image-build time, and record that substitution in the task's difficulty.json notes rather than switching repositories."),
    ("turret-moor", "scientific-python", "scientific_computing", "medium",
     "yt-project/yt", "yt-4.4.2", "12MB 1,243 files 182,702 LOC pyproject+setup+Makefile",
     "Do real scientific analysis inside a real astrophysics codebase, standing in for TB2.1's amusecode/amuse task. Clone yt pinned, install it and its runtime dependencies at build time, ship a small simulation dataset as an authored fixture, and require an analysis using yt's own API: load the dataset, compute a derived quantity, and write a result. Verifier recomputes the expected answer independently with numpy from the same fixture and compares across 3 hidden datasets, and asserts the agent used yt's API rather than reimplementing the loader."),
    ("tenon-orbit", "quantum-python", "scientific_computing", "medium",
     "qutip/qutip", "v5.3.1", "6MB 494 files 81,874 LOC pyproject+setup+Makefile",
     "Stands in for TB2.1's jcmgray/quimb task. Clone qutip pinned and require a quantum dynamics computation expressed in qutip's own objects: build a Hamiltonian, evolve a state, and extract an observable with a declared tolerance. Verifier checks the numeric result against an independently computed reference across 3 hidden parameter sets, and asserts the deliverable imports qutip and constructs its operators rather than hand-rolling the linear algebra."),
    ("quoin-vellum", "nlp-library", "data_science", "medium",
     "RaRe-Technologies/gensim", "4.4.0", "76MB 851 files 71,049 LOC pyproject+setup",
     "Stands in for TB2.1's facebookresearch/fastText task. Clone gensim pinned and require a real topic-modelling or embedding workflow on an authored corpus using gensim's own API, with a quality gate that a naive implementation misses. Verifier evaluates the agent's trained model on 3 hidden corpora against held-out coherence and retrieval thresholds, and asserts the model was serialized and reloaded through gensim's own format."),
    ("plinth-wicket", "js-security-suite", "security", "hard",
     "cure53/DOMPurify", "3.4.15", "1MB shallow 12 files 469 LOC package.json",
     "Stands in for TB2.1's davidwagner/html-sanitizer-testbed task. Clone DOMPurify pinned, install dev dependencies at build time so the trial runs offline, and require the agent to run the project's real test suite, then add a bypass test for a mutation class the suite does not cover and harden the configuration so the bypass fails while every existing test still passes. Verifier runs the project's own suite plus 3 hidden bypass payloads under jsdom, asserting sanitisation held and that no existing test was skipped, removed or weakened."),
    ("trunnel-reach", "binary-analysis", "security", "hard",
     "angr/angr", "v9.3.4", "12MB shallow 1,768 files 366,937 LOC pyproject+setup+Cargo+Makefile",
     "Stands in for TB2.1's klee/klee task. Clone angr pinned and install it at build time, then ship an authored binary with a non-obvious input constraint. Require the agent to solve it with angr's symbolic execution API rather than by brute force, and to write the solution as a reusable script. Verifier runs the agent's script against 3 hidden binaries built from the same generator with different constraints, asserts the recovered inputs satisfy each binary's check, and asserts the script imports angr and constrains the state rather than enumerating inputs."),
]


def main():
    existing = set(os.listdir(os.path.join(EVAL, 'tasks')))
    free = set(json.load(open('/tmp/cov/free_names_v42.json')))
    out, names = [], []
    for name, shape, cat, diff, repo, ref, probe, brief in SLOTS:
        if name in existing:
            print(f'FATAL: {name} already exists in tasks/', file=sys.stderr); return 2
        if name in names:
            print(f'FATAL: duplicate slot name {name}', file=sys.stderr); return 2
        if name not in free:
            print(f'FATAL: {name} is not on the verified free-name list', file=sys.stderr); return 2
        names.append(name)
        out.append(dict(name=name, shape=shape, category=cat, difficulty=diff,
                        repository=repo, ref=ref, probe=probe, brief=brief))
    # forbidden-list intersection is a hard error at plan time, not only at gate time
    forb = {t['repository'].lower() for t in
            json.load(open(os.path.join(EVAL, 'specs', 'tb21_source_repositories.json')))['tasks']}
    clash = [s['repository'].lower() for s in out
             if f"github.com/{s['repository'].lower()}" in forb
             or s['repository'].lower() in forb]
    if clash:
        print(f'FATAL: slot repos shared with the TB2.1 forbidden list: {clash}', file=sys.stderr)
        return 2
    print(f'slots={len(out)}  forbidden-list intersection=0')
    print('by category  :', dict(Counter(x['category'] for x in out).most_common()))
    print('by difficulty:', dict(Counter(x['difficulty'] for x in out)))
    print('by shape     :', dict(Counter(x['shape'] for x in out).most_common()))
    json.dump(out, open(os.path.join(EVAL, 'specs', 'v42_slots.json'), 'w'), indent=1)
    open(os.path.join(EVAL, 'specs', 'v42_slots.json'), 'a').write('\n')
    print('wrote specs/v42_slots.json')
    for x in out:
        print(f"  {x['name']:18s} {x['repository']:34s} {x['ref'][:24]:26s} {x['shape']}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
