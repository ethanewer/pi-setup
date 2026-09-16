#!/usr/bin/env python3
"""Build the library, framework and toolchain inventory for the whole suite.

Answers "what does this benchmark actually exercise, and in which tasks", which
was previously spread across four partial sources and one narrative report:

  specs/pinned_python_deps.json   pip packages only, Python only, keyed by base
  specs/upstream_sources.json     the upstream repositories tasks clone
  specs/tb21_competencies.json    tb2.1's competency inventory, which the v4.x
                                  families deliberately claim none of
  reports/v3.9_skill_gap_review.md  what was MISSING, not what is covered

Nothing listed apt packages, npm dependencies, Cargo or Go modules, Maven
dependencies, the services a task starts, or the build systems in use. This
derives all of it from the task tree so it cannot drift from what the tasks
actually do, and every entry carries the tasks that exercise it.

Outputs:
  specs/skill_inventory.json    machine-readable, one entry per skill with tasks
  reports/skill_inventory.md    readable, grouped by category

Usage:
  python3 tools/build_skill_inventory.py            # write both
  python3 tools/build_skill_inventory.py --stdout   # markdown only, no writes
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _toml_compat

ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / 'tasks'

# Source extensions, mapped to the language a reader would expect to see named.
LANG_BY_EXT = {
    '.py': 'Python', '.pyx': 'Cython', '.go': 'Go', '.rs': 'Rust',
    '.ts': 'TypeScript', '.tsx': 'TypeScript', '.js': 'JavaScript',
    '.jsx': 'JavaScript', '.mjs': 'JavaScript', '.cjs': 'JavaScript',
    '.java': 'Java', '.kt': 'Kotlin', '.scala': 'Scala', '.c': 'C',
    '.h': 'C/C++ header', '.cpp': 'C++', '.cc': 'C++', '.hpp': 'C++',
    '.cs': 'C#', '.rb': 'Ruby', '.php': 'PHP', '.pl': 'Perl', '.r': 'R',
    '.f90': 'Fortran', '.v': 'Verilog', '.sv': 'SystemVerilog',
    '.vhdl': 'VHDL', '.sh': 'Shell', '.sql': 'SQL', '.tex': 'TeX',
    '.lua': 'Lua', '.hs': 'Haskell', '.ml': 'OCaml', '.ex': 'Elixir',
    '.exs': 'Elixir', '.clj': 'Clojure', '.swift': 'Swift', '.m': 'Objective-C/MATLAB',
    '.css': 'CSS', '.html': 'HTML', '.s': 'assembly', '.S': 'assembly',
    '.lean': 'Lean', '.v': 'Verilog', '.proto': 'Protocol Buffers',
    '.zig': 'Zig', '.dart': 'Dart', '.jl': 'Julia', '.nim': 'Nim',
}

# Toolchain packages, by the ecosystem that installs them. Presence of one of
# these is stronger evidence of a language than a stray source file, because it
# means the task compiles or runs that language rather than merely shipping a
# fixture in it.
TOOLCHAIN = {
    'golang-go': 'Go', 'golang': 'Go', 'gcc': 'C', 'g++': 'C++', 'clang': 'C/C++ (LLVM)',
    'rustc': 'Rust', 'cargo': 'Rust', 'openjdk-21-jdk-headless': 'Java',
    'openjdk-17-jdk-headless': 'Java', 'openjdk-21-jre-headless': 'Java',
    'maven': 'Java (Maven)', 'r-base': 'R', 'r-base-core': 'R',
    'gfortran': 'Fortran', 'ocaml': 'OCaml', 'coq': 'Coq', 'nodejs': 'Node.js',
    'python3': 'Python', 'iverilog': 'Verilog', 'ghc': 'Haskell',
}

# Long-running services a task can start and drive. Detected from apt packages
# and from the task's own text, because a service may also arrive by pip or by a
# vendored binary.
SERVICES = {
    'postgresql': 'PostgreSQL', 'postgresql-16': 'PostgreSQL', 'postgres': 'PostgreSQL',
    'redis-server': 'Redis', 'redis': 'Redis', 'mariadb-server': 'MariaDB',
    'mysql-server': 'MySQL', 'nginx': 'nginx', 'apache2': 'Apache httpd',
    'prometheus': 'Prometheus', 'prometheus-alertmanager': 'Alertmanager',
    'supervisor': 'supervisord', 'mosquitto': 'MQTT (mosquitto)',
    'sqlite3': 'SQLite', 'rabbitmq-server': 'RabbitMQ',
}

BUILD_SYSTEMS = {
    'CMakeLists.txt': 'CMake', 'Makefile': 'Make', 'Makefile.am': 'Automake',
    'configure.ac': 'Autoconf', 'meson.build': 'Meson', 'pom.xml': 'Maven',
    'build.gradle': 'Gradle', 'build.sbt': 'sbt', 'pyproject.toml': 'pyproject (PEP 517/518)',
    'setup.py': 'setuptools', 'package.json': 'npm', 'Cargo.toml': 'Cargo',
    'go.mod': 'Go modules', 'tsconfig.json': 'tsc', 'BUILD.bazel': 'Bazel',
    'SConstruct': 'SCons', 'Rakefile': 'Rake', 'Gemfile': 'Bundler',
    'composer.json': 'Composer', 'mix.exs': 'Mix',
}

# Each capture stops at a shell operator rather than running to end of line.
# Without the lookahead a greedy `[^\n]*` swallowed a second install on the same
# line: `pip install -e '.[testing]' && pip install 'ruff==0.2.2'` produced one
# match covering both, and shell_strip then cut it at the `&&`, so the second
# install and everything in it vanished from the inventory.
_NO_OP = r'(?:(?!&&|\|\||[;|])[^\n])*'
APT_INSTALL = re.compile(r'apt-get\s+install(' + _NO_OP + r')')
PIP_INSTALL = re.compile(r'pip3?\s+install(' + _NO_OP + r')')
NPM_INSTALL = re.compile(r'npm\s+(?:install|i|ci)(' + _NO_OP + r')')
CARGO_INSTALL = re.compile(r'cargo\s+install(' + _NO_OP + r')')
GO_INSTALL = re.compile(r'go\s+install(' + _NO_OP + r')')


def normalize_dockerfile(text: str) -> str:
    """Make a Dockerfile readable line-by-line for the extractors above.

    Two things have to happen, in this order:

    1. Drop whole-line comments first. Docker strips comment lines even inside a
       backslash continuation, so a `#` on its own line is not a shell comment
       and must not survive into a joined command.
    2. Join backslash-newline continuations, so a multi-line RUN reads as one
       line.

    The first version of this tool got the order wrong in a subtler way: it used
    a single regex `(?:[^\n]|\\\n)*` to span continuations. `[^\n]` matches the
    backslash, so the following newline terminated the match and every
    multi-line install was truncated to its first line, which for a pinned
    requirements block is just `--no-cache-dir`. That silently dropped black,
    ruff and most apt packages from the inventory while still producing
    plausible-looking output. Normalizing first makes the extractors simple and
    makes this class of bug visible.
    """
    text = re.sub(r'(?m)^\s*#.*$', '', text)
    return re.sub(r'\\\s*\n\s*', ' ', text)

CLONE_URL = re.compile(
    r'(?:git\+)?(?:https?://|git@|ssh://git@)'
    r'(github\.com|gitlab\.com|bitbucket\.org)[:/]'
    r'([A-Za-z0-9_.\-]+)/([A-Za-z0-9_.\-]+?)(?:\.git)?'
    r'(?:[@/#?][^\s"\'`)\]]*)?(?=[\s"\'`)\],;]|$)')
DOWNLOAD = re.compile(r'\b(?:curl|wget)\b[^\n]*?(https?://[^\s"\'`]+)')
APT_NOISE = {
    'y', 'qq', 'no', 'install', 'recommends', 'no-install-recommends', 'update',
    'noninteractive', 'DEBIAN_FRONTEND', 'apt', 'get', 'dev', 'null', 'download',
    'only', 'auto', 'remove', 'purge', 's', 'y', 'fix', 'missing', 'ca',
    'certificates', 'download-only',
}

# Words that leak out of comments and shell operators after `pip install`. The
# first cut of this tool reported `the`, `is`, `and`, `so` and `true` as Python
# packages, which is the kind of plausible-looking output that gets believed.
PIP_STOPWORDS = {
    'the', 'a', 'an', 'is', 'are', 'and', 'or', 'but', 'so', 'true', 'false',
    'in', 'on', 'at', 'to', 'of', 'for', 'with', 'from', 'this', 'that', 'it',
    'be', 'as', 'not', 'we', 'you', 'if', 'then', 'else', 'fi', 'do', 'done',
    'echo', 'exit', 'set', 'e', 'x', 'o', 'pipefail', 'bash', 'sh', 'python',
    'python3', 'pip', 'pip3', 'install', 'no', 'cache', 'dir', 'yes', 'all',
    'any', 'some', 'each', 'per', 'via', 'use', 'used', 'using', 'run', 'make',
    'sudo', 'apt', 'apt-get', 'get', 'curl', 'wget', 'rm', 'mv', 'cp', 'mkdir',
    'test', 'tests', 'note', 'see', 'must', 'should', 'will', 'would', 'can',
    'cannot', 'when', 'where', 'which', 'who', 'whom', 'whose', 'what', 'why',
    'how', 'need', 'needs', 'needed', 'keep', 'keeps', 'kept', 'one', 'two',
    'three', 'first', 'second', 'third', 'last', 'next', 'only', 'just',
    'also', 'still', 'here', 'there', 'them', 'they', 'their', 'its', 'his',
    'her', 'my', 'your', 'our', 'was', 'were', 'been', 'being', 'have', 'has',
    'had', 'having', 'does', 'did', 'doing', 'up', 'out', 'off', 'over',
    'under', 'again', 'more', 'most', 'other', 'same', 'such', 'into', 'about',
    'after', 'before', 'while', 'until', 'against', 'between', 'both', 'either',
    'neither', 'nor', 'own', 'very', 'too', 'quite', 'rather', 'always',
    'never', 'often', 'once', 'twice', 'now', 'today', 'later', 'soon',
}

# Well-known frameworks and libraries, mapped to the substrings that would
# reveal them in ANY ecosystem. A framework can arrive by pip, by npm, by an apt
# package, or by cloning its upstream repository, and counting only one of those
# gives a wrong answer: this tool's first cut reported Django as uncovered
# because it only looked at pip, while sill-ember and corvette-towpath exercise
# it through cloned Django plugin repositories.
NOTABLE = {
    'Django': ['django'], 'Flask': ['flask'], 'FastAPI': ['fastapi'],
    'Starlette': ['starlette'], 'SQLAlchemy': ['sqlalchemy'],
    'Ansible': ['ansible'], 'SaltStack': ['salt'], 'Puppet': ['puppet'],
    'Chef': ['chef'], 'Terraform': ['terraform'], 'Kubernetes': ['kubernetes', 'k8s'],
    'Docker': ['docker'], 'Nix': ['nix'],
    'NumPy': ['numpy'], 'SciPy': ['scipy'], 'pandas': ['pandas'],
    'Matplotlib': ['matplotlib'], 'scikit-learn': ['scikit-learn', 'sklearn'],
    'PyTorch': ['torch'], 'TensorFlow': ['tensorflow', 'keras'],
    'Hugging Face Transformers': ['transformers'], 'XGBoost': ['xgboost'],
    'LightGBM': ['lightgbm'], 'JAX': ['jax'], 'statsmodels': ['statsmodels'],
    'Jupyter': ['jupyter', 'ipython', 'notebook'], 'SymPy': ['sympy'],
    'NLTK': ['nltk'], 'spaCy': ['spacy'], 'NetworkX': ['networkx'],
    'DuckDB': ['duckdb'], 'Polars': ['polars'], 'Arrow': ['pyarrow', 'arrow'],
    'pytest': ['pytest'], 'Hypothesis': ['hypothesis'], 'coverage.py': ['coverage'],
    'mypy': ['mypy'], 'ruff': ['ruff'], 'Black': ['black'], 'Flake8': ['flake8'],
    'Poetry': ['poetry'], 'pip': ['pip'], 'uv': ['uv'], 'setuptools': ['setuptools'],
    'Cython': ['cython'], 'Pydantic': ['pydantic'], 'httpx': ['httpx'],
    'Requests': ['requests'], 'urllib3': ['urllib3'], 'aiohttp': ['aiohttp'],
    'Celery': ['celery'], 'Redis': ['redis'], 'psycopg': ['psycopg'],
    'cryptography': ['cryptography'], 'Paramiko': ['paramiko'],
    'psutil': ['psutil'], 'Pillow': ['pillow'], 'BeautifulSoup': ['beautifulsoup'],
    'lxml': ['lxml'], 'Jinja': ['jinja'], 'Click': ['click'], 'Typer': ['typer'],
    'Rich': ['rich'], 'Tqdm': ['tqdm'], 'gRPC': ['grpc'], 'Thrift': ['thrift'],
    'React': ['react'], 'Vue': ['vue'], 'Angular': ['angular'], 'Svelte': ['svelte'],
    'Next.js': ['next'], 'Express': ['express'], 'TypeScript': ['typescript'],
    'Node.js': ['nodejs', 'node-'], 'ESLint': ['eslint'], 'Prettier': ['prettier'],
    'Vite': ['vite'], 'Webpack': ['webpack'], 'Jest': ['jest'], 'Vitest': ['vitest'],
    'DOMPurify': ['dompurify'], 'Playwright': ['playwright'], 'Puppeteer': ['puppeteer'],
    'D3': ['d3'], 'Three.js': ['three'], 'Tailwind': ['tailwind'],
    'Spring': ['spring'], 'Hibernate': ['hibernate'], 'Gradle': ['gradle'],
    'Maven': ['maven'], 'JUnit': ['junit'], 'Jackson': ['jackson'],
    'Tokio': ['tokio'], 'Serde': ['serde'], 'Clap': ['clap'],
    'Rails': ['rails'], 'Sinatra': ['sinatra'], 'RSpec': ['rspec'],
    'PHPUnit': ['phpunit'], 'Composer': ['composer'], 'Laravel': ['laravel'],
    'Gin': ['gin-gonic'], 'Echo': ['labstack/echo'], 'Cobra': ['spf13/cobra'],
    'Kong': ['kong'], 'Traefik': ['traefik'], 'nginx': ['nginx'],
    'PostgreSQL': ['postgres', 'psql'], 'MySQL': ['mysql'], 'MariaDB': ['mariadb'],
    'SQLite': ['sqlite'], 'MongoDB': ['mongo'], 'Elasticsearch': ['elasticsearch', 'elastic'],
    'Prometheus': ['prometheus'], 'Grafana': ['grafana'], 'RabbitMQ': ['rabbitmq'],
    'Kafka': ['kafka'], 'MQTT': ['mosquitto', 'mqtt'],
    'LLVM/Clang': ['llvm', 'clang'], 'GCC': ['gcc'], 'GDB': ['gdb'],
    'Valgrind': ['valgrind'], 'Git': ['/git', 'git-'], 'ripgrep': ['ripgrep'],
    'CMake': ['cmake'], 'Meson': ['meson'], 'Autoconf': ['autoconf', 'automake'],
    'Bazel': ['bazel'], 'Ninja': ['ninja'], 'sbt': ['sbt'],
    'OpenSSL': ['openssl'], 'curl': ['curl'], 'Zstandard': ['zstd', 'zstandard'],
    'zlib': ['zlib'], 'FFmpeg': ['ffmpeg'], 'OpenCV': ['opencv'],
    'SDL': ['sdl'], 'Vulkan': ['vulkan'], 'Protobuf': ['protobuf', 'proto-'],
    'meson-python': ['meson-python'], 'scikit-image': ['scikit-image', 'skimage'],
    'Sphinx': ['sphinx'], 'MkDocs': ['mkdocs'], 'pdoc': ['pdoc'],
    'Trivy': ['trivy'], 'Bandit': ['bandit'], 'Semgrep': ['semgrep'],
    'CodeQL': ['codeql'], 'OWASP Dependency-Check': ['dependency-check'],
    'Renovate': ['renovate'], 'dependabot': ['dependabot'],
    'Homebrew': ['brew'], 'pip-tools': ['pip-tools'],
    'tox': ['tox'], 'nox': ['nox'], 'pre-commit': ['pre-commit'],
    'Invoke': ['invoke'], 'Fabric': ['fabric'], 'Scrapy': ['scrapy'],
    'Tornado': ['tornado'], 'Uvicorn': ['uvicorn'], 'Gunicorn': ['gunicorn'],
    'Daphne': ['daphne'], 'Channels': ['channels'], 'WebSocket': ['websocket', 'websockets'],
    'SMTP': ['smtp', 'aiosmtpd'], 'LDAP': ['ldap'], 'Kerberos': ['kerberos'],
    'Samba': ['samba'], 'BIND': ['bind9'], 'dnsmasq': ['dnsmasq'],
    'OpenSSH': ['openssh'], 'systemd': ['systemd'], 'cron': ['cron'],
    'Istio': ['istio'], 'Envoy': ['envoy'], 'Consul': ['consul'],
    'Vault': ['vault'], 'Nomad': ['nomad'], 'etcd': ['etcd'],
    'ClickHouse': ['clickhouse'], 'Cassandra': ['cassandra'], 'Neo4j': ['neo4j'],
    'InfluxDB': ['influxdb'], 'TimescaleDB': ['timescale'],
    'Airflow': ['airflow'], 'Dagster': ['dagster'], 'Prefect': ['prefect'],
    'dbt': ['dbt'], 'Spark': ['spark'], 'Flink': ['flink'],
    'Ray': ['ray'], 'Dask': ['dask'], 'NumExpr': ['numexpr'],
    'ONNX': ['onnx'], 'Triton': ['triton'], 'TensorRT': ['tensorrt'],
    'llama.cpp': ['llama.cpp', 'llama-cpp'], 'Ollama': ['ollama'],
    'LangChain': ['langchain'], 'OpenAI SDK': ['openai'], 'Anthropic SDK': ['anthropic'],
    'Bootstrap': ['bootstrap'], 'jQuery': ['jquery'], 'HTMX': ['htmx'],
    'Alpine.js': ['alpine'], 'Astro': ['astro'], 'Nuxt': ['nuxt'],
    'Storybook': ['storybook'], 'Cypress': ['cypress'],
    'Qt': ['qt5', 'qt6', 'pyqt', 'pyside'], 'GTK': ['gtk'],
    'Electron': ['electron'], 'Tauri': ['tauri'],
    'Unity': ['unity'], 'Godot': ['godot'], 'Blender': ['blender'],
    'LaTeX': ['latex', 'texlive'], 'Pandoc': ['pandoc'],
    'Graphviz': ['graphviz'], 'PlantUML': ['plantuml'], 'Mermaid': ['mermaid'],
    'ROS': ['ros-'], 'OpenCV-Python': ['cv2'],
    'pytest-asyncio': ['pytest-asyncio'], 'pytest-cov': ['pytest-cov'],
    'pytest-xdist': ['pytest-xdist'], 'mock': ['mock'],
    'responses': ['responses'], 'requests-mock': ['requests-mock'],
    'freezegun': ['freezegun'], 'faker': ['faker'], 'factory_boy': ['factory'],
    'Selenium': ['selenium'], 'Appium': ['appium'],
    'Docker Compose': ['docker-compose', 'compose'],
    'GitHub Actions': ['actions/'], 'GitLab CI': ['gitlab-ci'],
    'Make': ['make'], 'Just': ['just'], 'Task': ['taskfile'],
    'YAML': ['yaml'], 'TOML': ['toml'], 'JSON Schema': ['jsonschema', 'json-schema'],
    'XML': ['xml', 'lxml'], 'Parquet': ['parquet'],
    'NetCDF': ['netcdf'], 'HDF5': ['hdf5', 'h5py'], 'FITS': ['fits', 'astropy'],
    'Astropy': ['astropy'], 'Biopython': ['biopython', 'bio'],
    'RDKit': ['rdkit'], 'OpenBabel': ['openbabel'],
    'GStreamer': ['gstreamer'], 'PulseAudio': ['pulseaudio'], 'ALSA': ['alsa'],
    'libuv': ['libuv'], 'ZeroMQ': ['zeromq', 'zmq'], 'nanomsg': ['nanomsg'],
    'Capstone': ['capstone'], 'Ghidra': ['ghidra'], 'Radare2': ['radare2'],
    'Frida': ['frida'], 'angr': ['angr'], 'Z3': ['z3'],
    'Boolector': ['boolector'], 'Yices': ['yices'],
    'Verilator': ['verilator'], 'Icarus Verilog': ['iverilog'],
    'Yosys': ['yosys'], 'cocotb': ['cocotb'],
    'Lean': ['lean'], 'Coq': ['coq'], 'Isabelle': ['isabelle'],
    'Agda': ['agda'], 'Rocq': ['rocq'],
}


def read(p: Path, limit: int = 4_000_000) -> str:
    try:
        if p.stat().st_size > limit:
            return ''
        return p.read_text(errors='replace')
    except OSError:
        return ''


def apt_tokens(seg: str) -> list[str]:
    seg = seg.replace('\\\n', ' ')
    out = []
    for tok in seg.split():
        tok = tok.strip('"\'')
        if not tok or tok.startswith('-') or tok.startswith('$'):
            continue
        if not re.match(r'^[a-z0-9][a-z0-9+.\-]*$', tok):
            continue
        if tok in APT_NOISE or '=' in tok:
            continue
        out.append(tok)
    return out


def shell_strip(seg: str) -> str:
    """Drop anything after a shell operator or an inline comment.

    `pip install foo && echo done # note the reason` yields only `foo`. Without
    this the words in the echo and the comment become package names, which is
    how the first cut of this tool came to report `the`, `is`, `and`, `so` and
    `true` as Python packages.
    """
    seg = re.split(r'#', seg)[0]
    seg = re.split(r'&&|\|\||;|\|', seg)[0]
    return seg


def pip_reqs(seg: str) -> list[str]:
    seg = shell_strip(seg)
    out = []
    skip_next = False
    for tok in seg.split():
        tok = tok.strip('"\'')
        if skip_next:
            skip_next = False
            continue
        if tok in ('-r', '-c', '-e', '-t', '--requirement', '--constraint',
                   '--target', '--index-url', '--extra-index-url', '-i'):
            skip_next = True
            continue
        if not tok or tok.startswith('-') or tok.startswith('http') or '/' in tok:
            continue
        if tok in ('.', '..'):
            continue
        name = tok.split('==')[0].split('>=')[0].split('<=')[0].split('~=')[0]
        name = re.sub(r'\[.*\]$', '', name)
        if name.lower() in PIP_STOPWORDS:
            continue
        if re.match(r'^[A-Za-z0-9][A-Za-z0-9_.\-]*$', name):
            out.append(name)
    return out


def deps_from_json(path: Path, keys: tuple[str, ...]) -> list[str]:
    try:
        d = json.loads(path.read_text())
    except Exception:
        return []
    out = []
    for k in keys:
        v = d.get(k)
        if isinstance(v, dict):
            out.extend(v.keys())
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stdout', action='store_true', help='print markdown, write nothing')
    args = ap.parse_args()

    skills: dict[str, dict] = {}

    def add(kind: str, name: str, task: str, detail: str = ''):
        if not name:
            return
        key = f'{kind}::{name}'
        e = skills.setdefault(key, {
            'kind': kind, 'name': name, 'tasks': set(), 'detail': detail or None})
        e['tasks'].add(task)
        if detail and not e.get('detail'):
            e['detail'] = detail

    task_names = sorted(p.name for p in TASKS.iterdir() if p.is_dir())
    cats = collections.Counter()
    diffs = collections.Counter()
    bases = collections.Counter()

    for t in task_names:
        td = TASKS / t
        toml_p = td / 'task.toml'
        if toml_p.exists():
            try:
                meta = _toml_compat.loads(toml_p.read_text()).get('metadata', {})
                cats[meta.get('category') or '(none)'] += 1
                diffs[meta.get('difficulty') or '(none)'] += 1
                for tag in meta.get('tags') or []:
                    if not tag.startswith('C-') and tag != t:
                        add('tag', tag, t)
            except Exception:
                pass

        df = td / 'environment' / 'Dockerfile'
        raw = read(df)
        dtext = normalize_dockerfile(raw) if raw else ''
        if dtext:
            for m in re.finditer(r'^\s*FROM\s+(\S+)', dtext, re.M):
                bases[m.group(1)] += 1
                add('base-image', m.group(1), t)
            for m in APT_INSTALL.finditer(dtext):
                for pkg in apt_tokens(m.group(1)):
                    add('apt', pkg, t)
                    if pkg in TOOLCHAIN:
                        add('language', TOOLCHAIN[pkg], t, f'via apt {pkg}')
                    if pkg in SERVICES:
                        add('service', SERVICES[pkg], t, f'apt {pkg}')
            for m in PIP_INSTALL.finditer(dtext):
                for req in pip_reqs(m.group(1)):
                    add('pip', req, t)
            for m in NPM_INSTALL.finditer(dtext):
                for tok in shell_strip(m.group(1)).split():
                    tok = tok.strip('"\'')
                    if not tok or tok.startswith('-'):
                        continue
                    # scoped packages keep their scope: @org/pkg@1.2 -> @org/pkg
                    if tok.startswith('@'):
                        nm = (tok.split('/')[0] + '/' + tok.split('/')[1].split('@')[0]
                              if '/' in tok else tok)
                        add('npm', nm, t)
                    else:
                        add('npm', tok.split('@')[0], t)
            for m in CARGO_INSTALL.finditer(dtext):
                for tok in shell_strip(m.group(1)).split():
                    if tok and not tok.startswith('-'):
                        add('cargo', tok, t)
            for m in GO_INSTALL.finditer(dtext):
                for tok in shell_strip(m.group(1)).split():
                    if tok and not tok.startswith('-') and '/' in tok:
                        add('go-module', tok, t)
            for m in CLONE_URL.finditer(dtext):
                add('upstream-repository',
                    f'{m.group(1)}/{m.group(2)}/{m.group(3).removesuffix(".git")}', t)
            for m in DOWNLOAD.finditer(dtext):
                host = re.sub(r'^https?://', '', m.group(1)).split('/')[0]
                add('download-host', host, t)
            if re.search(r'\brustup\b', dtext):
                add('language', 'Rust', t, 'via rustup')
            if re.search(r'\bnvm\b|\bnpm\b|\bnode\b', dtext):
                add('language', 'Node.js', t)

        # fixture-tree evidence: languages, build systems, package manifests
        env = td / 'environment' / 'files'
        if env.is_dir():
            langs = collections.Counter()
            for dp, dn, fn in os.walk(env):
                dn[:] = [d for d in dn if d not in ('.git', '__pycache__', 'node_modules')]
                for f in fn:
                    ext = os.path.splitext(f)[1]
                    if ext in LANG_BY_EXT:
                        langs[LANG_BY_EXT[ext]] += 1
                    if f in BUILD_SYSTEMS:
                        add('build-system', BUILD_SYSTEMS[f], t)
                    if f == 'package.json':
                        for d in deps_from_json(Path(dp) / f,
                                                ('dependencies', 'devDependencies')):
                            add('npm', d, t)
                    if f == 'Cargo.toml':
                        txt = read(Path(dp) / f)
                        sec = re.search(r'\[dependencies\](.*?)(?:\n\[|\Z)', txt, re.S)
                        if sec:
                            for line in sec.group(1).splitlines():
                                m = re.match(r'\s*([A-Za-z0-9_\-]+)\s*=', line)
                                if m:
                                    add('cargo', m.group(1), t)
                    if f == 'go.mod':
                        txt = read(Path(dp) / f)
                        for m in re.finditer(r'^\s*([a-z0-9.\-]+\.[a-z]{2,}/\S+)', txt, re.M):
                            add('go-module', m.group(1), t)
                    if f == 'pom.xml':
                        txt = read(Path(dp) / f)
                        for m in re.finditer(r'<artifactId>([^<]+)</artifactId>', txt):
                            add('maven', m.group(1), t)
                    if f == 'requirements.txt':
                        for line in read(Path(dp) / f).splitlines():
                            line = line.strip()
                            if line and not line.startswith('#') and not line.startswith('-'):
                                add('pip', re.split(r'[=<>~\[]', line)[0], t)
            for lang, n in langs.items():
                add('language', lang, t, f'{n} fixture file(s)')

        # services named in the instruction or verifier, which catches the ones
        # that arrive by pip or as a vendored binary rather than by apt
        text = read(td / 'instruction.md') + read(td / 'tests' / 'test.sh')
        low = text.lower()
        for needle, label in (('postgresql', 'PostgreSQL'), ('psql', 'PostgreSQL'),
                              ('redis', 'Redis'), ('mariadb', 'MariaDB'),
                              ('mysql', 'MySQL'), ('nginx', 'nginx'),
                              ('prometheus', 'Prometheus'), ('promtool', 'Prometheus'),
                              ('supervisord', 'supervisord'), ('duckdb', 'DuckDB'),
                              ('sqlite', 'SQLite'), ('mosquitto', 'MQTT (mosquitto)'),
                              ('terraform', 'Terraform')):
            if needle in low:
                add('service', label, t, 'named in instruction or verifier')

    # merge in the authoritative pip pins, which resolve versions per base image
    pins_p = ROOT / 'specs' / 'pinned_python_deps.json'
    if pins_p.exists():
        try:
            pins = json.loads(pins_p.read_text())
            versions: dict[str, set] = collections.defaultdict(set)
            for _key, pkgs in (pins.get('versions') or {}).items():
                if isinstance(pkgs, dict):
                    for name, ver in pkgs.items():
                        versions[name].add(str(ver))
            for key, e in skills.items():
                if e['kind'] == 'pip' and e['name'] in versions:
                    e['pinned_versions'] = sorted(versions[e['name']])
        except Exception:
            pass

    # merge in the disjointness-verified upstream inventory
    up_p = ROOT / 'specs' / 'upstream_sources.json'
    upstream_repos: set[str] = set()
    if up_p.exists():
        try:
            up = json.loads(up_p.read_text())
            upstream_repos = set(up.get('repositories') or [])
        except Exception:
            pass

    out = []
    for key in sorted(skills):
        e = skills[key]
        rec = {'kind': e['kind'], 'name': e['name'], 'task_count': len(e['tasks']),
               'tasks': sorted(e['tasks'])}
        if e.get('detail'):
            rec['detail'] = e['detail']
        if e.get('pinned_versions'):
            rec['pinned_versions'] = e['pinned_versions']
        if e['kind'] == 'upstream-repository':
            full = f'github.com/{e["name"].split("github.com/")[-1]}'
            rec['in_upstream_sources'] = any(
                e['name'].lower().endswith(r.split('/', 1)[-1].lower())
                for r in upstream_repos)
        out.append(rec)

    summary = {
        'generated_from': 'the task tree; regenerate with tools/build_skill_inventory.py',
        'task_count': len(task_names),
        'categories': dict(cats.most_common()),
        'difficulties': dict(diffs.most_common()),
        'base_images': dict(bases.most_common()),
        'skill_counts_by_kind': dict(collections.Counter(r['kind'] for r in out).most_common()),
        'upstream_repositories_in_specs': len(upstream_repos),
    }


    KIND_ORDER = ['language', 'upstream-repository', 'service', 'build-system',
                  'base-image', 'pip', 'npm', 'cargo', 'go-module', 'maven', 'apt',
                  'download-host', 'tag']
    TITLES = {
        'language': 'Languages',
        'upstream-repository': 'Upstream repositories cloned at image-build time',
        'service': 'Services and datastores a task starts and drives',
        'build-system': 'Build systems',
        'base-image': 'Base images',
        'pip': 'Python packages (pip)',
        'npm': 'JavaScript packages (npm)',
        'cargo': 'Rust crates (Cargo)',
        'go-module': 'Go modules',
        'maven': 'Maven artifacts',
        'apt': 'apt packages',
        'download-host': 'Hosts a Dockerfile downloads from',
        'tag': 'Task tags',
    }

    md = ['# Skill inventory', '',
          f'Generated from the {len(task_names)} task directories by',
          '`tools/build_skill_inventory.py`. Every entry lists the tasks that',
          'exercise it, so a skill can be traced to evidence rather than asserted.',
          '',
          'This is a snapshot of a moving tree: regenerate it after any wave lands.',
          '',
          '## Summary', '',
          f'- Tasks: **{len(task_names)}**',
          f'- Distinct skills recorded: **{len(out)}**',
          f'- Upstream repositories cloned: **{summary["upstream_repositories_in_specs"]}**',
          '',
          '| Category | Tasks |', '|---|---|']
    for k, v in summary['categories'].items():
        md.append(f'| {k} | {v} |')
    md += ['', '| Difficulty | Tasks |', '|---|---|']
    for k, v in summary['difficulties'].items():
        md.append(f'| {k} | {v} |')
    md += ['', '| Base image | Tasks |', '|---|---|']
    for k, v in summary['base_images'].items():
        md.append(f'| `{k}` | {v} |')

    # Cross-reference the well-known frameworks against EVERY ecosystem, so a
    # reader asking "is X covered?" gets an answer rather than having to know
    # which ecosystem X happened to arrive through.
    notable_rows = []
    for fw, pats in sorted(NOTABLE.items()):
        # Tags are excluded: they are free text and produced a false positive on
        # the first run, where the tag
        # `express-an-integrand-and-interval-as-symbolic-sympy-objects` counted as
        # evidence for the Express web framework. Substring matching over free
        # text is not evidence about a library.
        hits = [r for r in out
                if r['kind'] != 'tag'
                and any(p in r['name'].lower() for p in pats)]
        if not hits:
            continue
        tasks = set()
        for h in hits:
            tasks |= set(h['tasks'])
        where = collections.Counter(h['kind'] for h in hits)
        notable_rows.append({
            'framework': fw,
            'matching_skills': len(hits),
            'task_count': len(tasks),
            'ecosystems': dict(where.most_common()),
            'examples': sorted({h['name'] for h in hits})[:6],
            'tasks': sorted(tasks),
        })
    covered = {r['framework'] for r in notable_rows}
    missing = sorted(set(NOTABLE) - covered)

    md += ['', '## Notable frameworks and libraries', '',
           'Cross-referenced across every ecosystem below, so a framework that',
           'arrives by cloning its upstream repository counts as covered exactly',
           'as one that arrives by pip does. Counting a single ecosystem gives a',
           'wrong answer: an earlier cut of this tool reported Django as',
           'uncovered because it looked only at pip, while `sill-ember` and',
           '`corvette-towpath` exercise it through cloned Django plugin repos.',
           '',
           f'Covered with evidence: **{len(covered)}** of {len(NOTABLE)} checked.',
           f'No evidence found: **{len(missing)}**.', '',
           '"No evidence" means nothing in this inventory matched the name. It is',
           'not proof the suite never touches the technology; it means no package,',
           'apt entry, cloned repository, fixture manifest or service reference',
           'names it.', '',
           '| Framework | Tasks | Matching skills | Ecosystems | Examples |',
           '|---|---|---|---|---|']
    for r in sorted(notable_rows, key=lambda x: (-x['task_count'], x['framework'])):
        eco = ', '.join(f'{k} x{v}' for k, v in r['ecosystems'].items())
        ex = ', '.join(f'`{e}`' for e in r['examples'])
        md.append(f'| {r["framework"]} | {r["task_count"]} | {r["matching_skills"]} '
                  f'| {eco} | {ex} |')
    md += ['', f'### Checked and found no evidence ({len(missing)})', '',
           ', '.join(f'`{m}`' for m in missing), '',
           'These are candidate gaps, not confirmed ones. Confirm by reading the',
           'tasks before treating any of them as missing.']

    md += ['', '### Caveat: code generated at image-build time is invisible here', '',
           'This inventory reads what ships in the task tree. A task that',
           'generates its source during the image build is under-represented.',
           'The clearest case is `cistern-loom`, which ships a 2,100-line Python',
           'generator and produces roughly 46,000 lines of TypeScript, Vue, Svelte',
           'and CSS inside the image, none of which exist as fixture files. So the',
           'TypeScript and CSS counts below reflect shipped fixtures only and',
           'understate what the suite actually asks an agent to read.']

    for kind in KIND_ORDER:
        rows = [r for r in out if r['kind'] == kind]
        if not rows:
            continue
        # Tags are free text and mostly one-per-task, so 1518 of the 2025 entries
        # in the first cut were task-id noise. Only tags shared by two or more
        # tasks say anything about the suite.
        if kind == 'tag':
            rows = [r for r in rows if r['task_count'] >= 2]
            if not rows:
                continue
        rows.sort(key=lambda r: (-r['task_count'], r['name'].lower()))
        md += ['', f'## {TITLES.get(kind, kind)}', '',
               f'{len(rows)} distinct entries.', '',
               '| Skill | Tasks | Example tasks |', '|---|---|---|']
        for r in rows:
            ex = ', '.join(f'`{x}`' for x in r['tasks'][:4])
            if len(r['tasks']) > 4:
                ex += ', …'
            extra = ''
            if r.get('pinned_versions'):
                extra = ' (' + ', '.join(r['pinned_versions'][:3]) + ')'
            md.append(f'| `{r["name"]}`{extra} | {r["task_count"]} | {ex} |')

    markdown = '\n'.join(md) + '\n'

    if args.stdout:
        print(markdown)
        return 0

    (ROOT / 'specs' / 'skill_inventory.json').write_text(
        json.dumps({'summary': summary, 'notable': notable_rows,
                    'notable_no_evidence': missing, 'skills': out}, indent=1) + '\n')
    (ROOT / 'reports' / 'skill_inventory.md').write_text(markdown)
    print(f'tasks={len(task_names)} skills={len(out)} '
          f'notable_covered={len(covered)}/{len(NOTABLE)} '
          f'kinds={dict(summary["skill_counts_by_kind"])}')
    print('wrote specs/skill_inventory.json and reports/skill_inventory.md')
    return 0


if __name__ == '__main__':
    sys.exit(main())
