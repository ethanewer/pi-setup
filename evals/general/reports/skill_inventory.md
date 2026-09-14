# Skill inventory

Generated from the 1075 task directories by
`tools/build_skill_inventory.py`. Every entry lists the tasks that
exercise it, so a skill can be traced to evidence rather than asserted.

This is a snapshot of a moving tree: regenerate it after any wave lands.

## Summary

- Tasks: **1075**
- Distinct skills recorded: **2225**
- Upstream repositories cloned: **79**

| Category | Tasks |
|---|---|
| debugging | 234 |
| programming | 202 |
| data_processing | 142 |
| data_science | 125 |
| system_administration | 117 |
| security | 85 |
| scientific_computing | 82 |
| web | 45 |
| file_operations | 25 |
| reasoning | 17 |
| dependency_management | 1 |

| Difficulty | Tasks |
|---|---|
| medium | 477 |
| easy | 307 |
| hard | 291 |

| Base image | Tasks |
|---|---|
| `bench-base:python-3.12` | 782 |
| `bench-base:ubuntu-24.04` | 254 |
| `bench-base:node-22` | 38 |
| `golang:1.26.3@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a` | 1 |
| `texlive/texlive` | 1 |

## Notable frameworks and libraries

Cross-referenced across every ecosystem below, so a framework that
arrives by cloning its upstream repository counts as covered exactly
as one that arrives by pip does. Counting a single ecosystem gives a
wrong answer: an earlier cut of this tool reported Django as
uncovered because it looked only at pip, while `sill-ember` and
`corvette-towpath` exercise it through cloned Django plugin repos.

Covered with evidence: **125** of 276 checked.
No evidence found: **151**.

"No evidence" means nothing in this inventory matched the name. It is
not proof the suite never touches the technology; it means no package,
apt entry, cloned repository, fixture manifest or service reference
names it.

| Framework | Tasks | Matching skills | Ecosystems | Examples |
|---|---|---|---|---|
| NumPy | 166 | 3 | pip x2, apt x1 | `numpy`, `numpydoc`, `python3-numpy` |
| pytest | 141 | 20 | pip x18, apt x1, upstream-repository x1 | `github.com/pytest-dev/pytest`, `pytest`, `pytest-aiohttp`, `pytest-asyncio`, `pytest-benchmark`, `pytest-cov` |
| GCC | 92 | 4 | apt x4 | `gcc`, `gcc-aarch64-linux-gnu`, `gcc-mips-linux-gnu`, `gcc-mipsel-linux-gnu` |
| curl | 84 | 3 | apt x2, upstream-repository x1 | `curl`, `github.com/curl/curl`, `libcurl4-openssl-dev` |
| Make | 73 | 5 | apt x3, build-system x2 | `CMake`, `Make`, `automake`, `cmake`, `make` |
| setuptools | 65 | 6 | pip x4, build-system x1, upstream-repository x1 | `github.com/pypa/setuptools`, `setuptools`, `setuptools-scm`, `setuptools_scm`, `types-setuptools` |
| SciPy | 49 | 2 | pip x1, upstream-repository x1 | `github.com/scipy/scipy`, `scipy` |
| PyTorch | 48 | 3 | pip x2, upstream-repository x1 | `github.com/pytorch/vision`, `torch`, `torchvision` |
| Node.js | 41 | 2 | apt x1, base-image x1 | `bench-base:node-22`, `nodejs` |
| pandas | 40 | 1 | pip x1 | `pandas` |
| SQLite | 36 | 4 | apt x2, maven x1, service x1 | `SQLite`, `libsqlite3-0`, `sqlite-jdbc`, `sqlite3` |
| pytest-xdist | 29 | 1 | pip x1 | `pytest-xdist` |
| Ninja | 28 | 2 | apt x1, pip x1 | `ninja`, `ninja-build` |
| OpenSSL | 28 | 3 | apt x2, pip x1 | `libcurl4-openssl-dev`, `openssl`, `pyOpenSSL` |
| Requests | 26 | 4 | pip x3, upstream-repository x1 | `github.com/psf/requests`, `requests`, `requests-toolbelt`, `types-requests` |
| Cython | 25 | 4 | pip x3, language x1 | `Cython`, `cython`, `cython-lint` |
| Meson | 22 | 3 | pip x2, apt x1 | `meson`, `meson-python` |
| YAML | 21 | 2 | pip x2 | `PyYAML`, `pyyaml` |
| Flask | 18 | 2 | apt x1, pip x1 | `flask`, `python3-flask` |
| Pillow | 18 | 1 | pip x1 | `pillow` |
| meson-python | 18 | 1 | pip x1 | `meson-python` |
| pip | 18 | 2 | apt x1, upstream-repository x1 | `github.com/pypa/pip`, `python3-pip` |
| scikit-learn | 18 | 1 | pip x1 | `scikit-learn` |
| CMake | 16 | 2 | apt x1, build-system x1 | `CMake`, `cmake` |
| XML | 16 | 4 | pip x3, apt x1 | `defusedxml`, `libxml2-dev`, `lxml`, `xmlschema` |
| Hugging Face Transformers | 15 | 2 | pip x2 | `sentence-transformers`, `transformers` |
| PostgreSQL | 15 | 3 | apt x2, service x1 | `PostgreSQL`, `postgresql`, `postgresql-client` |
| Zstandard | 15 | 3 | apt x2, pip x1 | `libzstd-dev`, `zstandard`, `zstd` |
| mock | 15 | 3 | pip x3 | `mock`, `pytest-mock`, `types-mock` |
| Hypothesis | 14 | 1 | pip x1 | `hypothesis` |
| coverage.py | 13 | 1 | pip x1 | `coverage` |
| Maven | 12 | 8 | maven x4, apt x1, build-system x1, download-host x1, language x1 | `Java (Maven)`, `Maven`, `maven`, `maven-compiler-plugin`, `maven-enforcer-plugin`, `maven-jar-plugin` |
| Click | 11 | 2 | pip x1, upstream-repository x1 | `click`, `github.com/pallets/click` |
| Jupyter | 11 | 6 | pip x6 | `ipython`, `jupyter`, `jupyter_client`, `jupyter_core`, `jupyter_server`, `notebook` |
| LLVM/Clang | 10 | 8 | apt x7, language x1 | `C/C++ (LLVM)`, `clang`, `clang-16`, `clang-18`, `llvm`, `llvm-16` |
| Matplotlib | 10 | 2 | pip x1, upstream-repository x1 | `github.com/matplotlib/matplotlib`, `matplotlib` |
| NetworkX | 10 | 2 | pip x1, upstream-repository x1 | `github.com/networkx/networkx`, `networkx` |
| gRPC | 10 | 3 | pip x2, go-module x1 | `google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest`, `grpcio`, `grpcio-tools` |
| pytest-cov | 10 | 1 | pip x1 | `pytest-cov` |
| OpenSSH | 9 | 2 | apt x2 | `openssh-client`, `openssh-server` |
| TOML | 9 | 3 | pip x3 | `tomli`, `tomli-w`, `tomlkit` |
| Autoconf | 8 | 2 | apt x2 | `autoconf`, `automake` |
| JSON Schema | 8 | 3 | pip x2, apt x1 | `fastjsonschema`, `jsonschema`, `python3-jsonschema` |
| Jinja | 8 | 4 | pip x2, apt x1, upstream-repository x1 | `Jinja2`, `github.com/pallets/jinja`, `jinja2`, `python3-jinja2` |
| Protobuf | 8 | 3 | apt x1, go-module x1, pip x1 | `google.golang.org/protobuf/cmd/protoc-gen-go@latest`, `protobuf`, `protobuf-compiler` |
| SymPy | 8 | 3 | apt x1, pip x1, upstream-repository x1 | `github.com/sympy/sympy`, `python3-sympy`, `sympy` |
| cryptography | 8 | 1 | pip x1 | `cryptography` |
| uv | 8 | 3 | pip x2, upstream-repository x1 | `github.com/astral-sh/uv`, `uv`, `uvicorn` |
| zlib | 8 | 1 | apt x1 | `zlib1g-dev` |
| DuckDB | 7 | 3 | pip x1, service x1, upstream-repository x1 | `DuckDB`, `duckdb`, `github.com/duckdb/duckdb` |
| GDB | 7 | 1 | apt x1 | `gdb` |
| Tqdm | 7 | 1 | pip x1 | `tqdm` |
| nginx | 7 | 2 | apt x1, service x1 | `nginx` |
| psycopg | 7 | 3 | apt x1, pip x1, upstream-repository x1 | `github.com/psycopg/psycopg`, `psycopg2-binary`, `python3-psycopg2` |
| ripgrep | 7 | 1 | upstream-repository x1 | `github.com/BurntSushi/ripgrep` |
| Arrow | 6 | 1 | pip x1 | `pyarrow` |
| Prometheus | 6 | 4 | apt x1, pip x1, service x1, upstream-repository x1 | `Prometheus`, `github.com/prometheus/prometheus`, `prometheus`, `prometheus-client` |
| Redis | 6 | 4 | apt x1, pip x1, service x1, upstream-repository x1 | `Redis`, `github.com/redis/redis`, `redis`, `redis-server` |
| Z3 | 6 | 4 | apt x2, pip x1, upstream-repository x1 | `github.com/Z3Prover/z3`, `python3-z3`, `z3`, `z3-solver` |
| mypy | 6 | 4 | pip x3, upstream-repository x1 | `github.com/python/mypy`, `mypy`, `mypy-extensions`, `mypy_extensions` |
| urllib3 | 6 | 1 | pip x1 | `urllib3` |
| Astro | 5 | 2 | pip x2 | `astroid`, `astropy` |
| BeautifulSoup | 5 | 1 | pip x1 | `beautifulsoup4` |
| FFmpeg | 5 | 1 | apt x1 | `ffmpeg` |
| JUnit | 5 | 3 | maven x2, upstream-repository x1 | `github.com/junit-team/junit5`, `junit-jupiter`, `junit-platform-launcher` |
| NLTK | 5 | 1 | upstream-repository x1 | `github.com/nltk/nltk` |
| Poetry | 5 | 3 | upstream-repository x2, pip x1 | `github.com/python-poetry/poetry`, `github.com/python-poetry/poetry-core`, `poetry-core` |
| React | 5 | 7 | npm x7 | `@testing-library/react`, `@types/react`, `@types/react-dom`, `@vitejs/plugin-react`, `react`, `react-dom` |
| Rich | 5 | 1 | pip x1 | `rich` |
| lxml | 5 | 1 | pip x1 | `lxml` |
| psutil | 5 | 2 | pip x1, upstream-repository x1 | `github.com/giampaolo/psutil`, `psutil` |
| pytest-asyncio | 5 | 1 | pip x1 | `pytest-asyncio` |
| responses | 5 | 1 | pip x1 | `responses` |
| Bandit | 4 | 1 | upstream-repository x1 | `github.com/PyCQA/bandit` |
| Coq | 4 | 2 | apt x1, language x1 | `Coq`, `coq` |
| DOMPurify | 4 | 1 | upstream-repository x1 | `github.com/cure53/DOMPurify` |
| Express | 4 | 1 | upstream-repository x1 | `github.com/expressjs/express` |
| Flake8 | 4 | 2 | pip x1, upstream-repository x1 | `flake8`, `github.com/PyCQA/flake8` |
| Gin | 4 | 1 | upstream-repository x1 | `github.com/gin-gonic/gin` |
| Git | 4 | 1 | upstream-repository x1 | `github.com/git/git` |
| GitHub Actions | 4 | 1 | upstream-repository x1 | `github.com/actions/go-versions` |
| Jest | 4 | 4 | npm x3, upstream-repository x1 | `@jest/get-type`, `@jest/types`, `@testing-library/jest-dom`, `github.com/jestjs/jest` |
| OpenCV | 4 | 1 | pip x1 | `opencv-python-headless` |
| Prettier | 4 | 1 | upstream-repository x1 | `github.com/prettier/prettier` |
| SQLAlchemy | 4 | 1 | upstream-repository x1 | `github.com/sqlalchemy/sqlalchemy` |
| Semgrep | 4 | 1 | upstream-repository x1 | `github.com/semgrep/semgrep` |
| Triton | 4 | 1 | pip x1 | `triton` |
| Trivy | 4 | 1 | upstream-repository x1 | `github.com/aquasecurity/trivy` |
| TypeScript | 4 | 2 | language x1, npm x1 | `TypeScript`, `typescript` |
| Uvicorn | 4 | 1 | pip x1 | `uvicorn` |
| Valgrind | 4 | 1 | apt x1 | `valgrind` |
| Vite | 4 | 3 | npm x3 | `@vitejs/plugin-react`, `vite`, `vitest` |
| aiohttp | 4 | 3 | pip x2, upstream-repository x1 | `aiohttp`, `github.com/aio-libs/aiohttp`, `pytest-aiohttp` |
| httpx | 4 | 1 | upstream-repository x1 | `github.com/encode/httpx` |
| scikit-image | 4 | 1 | upstream-repository x1 | `github.com/scikit-image/scikit-image` |
| Biopython | 3 | 1 | pip x1 | `biopython` |
| Clap | 3 | 1 | upstream-repository x1 | `github.com/clap-rs/clap` |
| Cobra | 3 | 1 | upstream-repository x1 | `github.com/spf13/cobra` |
| RDKit | 3 | 1 | pip x1 | `rdkit` |
| Vitest | 3 | 1 | npm x1 | `vitest` |
| freezegun | 3 | 1 | pip x1 | `freezegun` |
| statsmodels | 3 | 1 | upstream-repository x1 | `github.com/statsmodels/statsmodels` |
| Astropy | 2 | 1 | pip x1 | `astropy` |
| ESLint | 2 | 1 | upstream-repository x1 | `github.com/eslint/eslint` |
| FITS | 2 | 1 | pip x1 | `astropy` |
| LaTeX | 2 | 4 | apt x3, base-image x1 | `texlive-fonts-recommended`, `texlive-latex-base`, `texlive-latex-recommended`, `texlive/texlive` |
| Playwright | 2 | 1 | pip x1 | `playwright` |
| Serde | 2 | 1 | upstream-repository x1 | `github.com/serde-rs/serde` |
| spaCy | 2 | 3 | pip x2, upstream-repository x1 | `github.com/explosion/spaCy`, `spacy-legacy`, `spacy-loggers` |
| Black | 1 | 1 | pip x1 | `black` |
| D3 | 1 | 1 | base-image x1 | `golang:1.26.3@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a` |
| Icarus Verilog | 1 | 1 | apt x1 | `iverilog` |
| JAX | 1 | 3 | pip x3 | `jax`, `jaxley`, `jaxlib` |
| Kafka | 1 | 1 | upstream-repository x1 | `github.com/apache/kafka` |
| Lean | 1 | 1 | language x1 | `Lean` |
| MQTT | 1 | 3 | apt x1, pip x1, service x1 | `MQTT (mosquitto)`, `mosquitto`, `paho-mqtt` |
| MariaDB | 1 | 3 | apt x2, service x1 | `MariaDB`, `mariadb-client`, `mariadb-server` |
| MySQL | 1 | 1 | service x1 | `MySQL` |
| Pydantic | 1 | 2 | pip x2 | `pydantic`, `pydantic_core` |
| Spark | 1 | 1 | pip x1 | `pyspark` |
| Terraform | 1 | 1 | service x1 | `Terraform` |
| Typer | 1 | 2 | pip x2 | `typer`, `typer-slim` |
| ZeroMQ | 1 | 1 | apt x1 | `libzmq5` |
| angr | 1 | 1 | upstream-repository x1 | `github.com/angr/angr` |
| ruff | 1 | 2 | pip x2 | `pytest-ruff`, `ruff` |

### Checked and found no evidence (151)

`ALSA`, `Agda`, `Airflow`, `Alpine.js`, `Angular`, `Ansible`, `Anthropic SDK`, `Appium`, `BIND`, `Bazel`, `Blender`, `Boolector`, `Bootstrap`, `Capstone`, `Cassandra`, `Celery`, `Channels`, `Chef`, `ClickHouse`, `CodeQL`, `Composer`, `Consul`, `Cypress`, `Dagster`, `Daphne`, `Dask`, `Django`, `Docker`, `Docker Compose`, `Echo`, `Elasticsearch`, `Electron`, `Envoy`, `Fabric`, `FastAPI`, `Flink`, `Frida`, `GStreamer`, `GTK`, `Ghidra`, `GitLab CI`, `Godot`, `Gradle`, `Grafana`, `Graphviz`, `Gunicorn`, `HDF5`, `HTMX`, `Hibernate`, `Homebrew`, `InfluxDB`, `Invoke`, `Isabelle`, `Istio`, `Jackson`, `Just`, `Kerberos`, `Kong`, `Kubernetes`, `LDAP`, `LangChain`, `Laravel`, `LightGBM`, `Mermaid`, `MkDocs`, `MongoDB`, `Neo4j`, `NetCDF`, `Next.js`, `Nix`, `Nomad`, `NumExpr`, `Nuxt`, `ONNX`, `OWASP Dependency-Check`, `Ollama`, `OpenAI SDK`, `OpenBabel`, `OpenCV-Python`, `PHPUnit`, `Pandoc`, `Paramiko`, `Parquet`, `PlantUML`, `Polars`, `Prefect`, `PulseAudio`, `Puppet`, `Puppeteer`, `Qt`, `ROS`, `RSpec`, `RabbitMQ`, `Radare2`, `Rails`, `Ray`, `Renovate`, `Rocq`, `SDL`, `SMTP`, `SaltStack`, `Samba`, `Scrapy`, `Selenium`, `Sinatra`, `Sphinx`, `Spring`, `Starlette`, `Storybook`, `Svelte`, `Tailwind`, `Task`, `Tauri`, `TensorFlow`, `TensorRT`, `Three.js`, `Thrift`, `TimescaleDB`, `Tokio`, `Tornado`, `Traefik`, `Unity`, `Vault`, `Verilator`, `Vue`, `Vulkan`, `WebSocket`, `Webpack`, `XGBoost`, `Yices`, `Yosys`, `cocotb`, `cron`, `dbt`, `dependabot`, `dnsmasq`, `etcd`, `factory_boy`, `faker`, `jQuery`, `libuv`, `llama.cpp`, `nanomsg`, `nox`, `pdoc`, `pip-tools`, `pre-commit`, `requests-mock`, `sbt`, `systemd`, `tox`

These are candidate gaps, not confirmed ones. Confirm by reading the
tasks before treating any of them as missing.

### Caveat: code generated at image-build time is invisible here

This inventory reads what ships in the task tree. A task that
generates its source during the image build is under-represented.
The clearest case is `cistern-loom`, which ships a 2,100-line Python
generator and produces roughly 46,000 lines of TypeScript, Vue, Svelte
and CSS inside the image, none of which exist as fixture files. So the
TypeScript and CSS counts below reflect shipped fixtures only and
understate what the suite actually asks an agent to read.

## Languages

28 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `Python` | 338 | `alewife-dune`, `amber-cistern`, `amber-engine`, `amber-guest`, … |
| `C` | 104 | `arid-orchid`, `ashen-vane`, `ballast-deepwater`, `basalt-cipher`, … |
| `Shell` | 71 | `ballast-caboose`, `ballast-fathom`, `bracket-cairn`, `bracket-coral`, … |
| `Node.js` | 45 | `amber-ledge`, `arid-jetty`, `ashen-lattice`, `ballast-drift`, … |
| `C++` | 40 | `ballast-brackish`, `ballast-deepwater`, `basalt-cipher`, `berm-coaming`, … |
| `Rust` | 27 | `alewife-anchorage`, `ballast-anchorage`, `ballast-current`, `bracket-basin`, … |
| `Java` | 23 | `ballast-caboose`, `ballast-hull`, `ballast-mooring`, `bracket-cairn`, … |
| `JavaScript` | 17 | `ballast-drift`, `bracket-beacon`, `bracket-bight`, `capstan-mooring`, … |
| `HTML` | 15 | `arid-cipher`, `basalt-bridge`, `derrick-tarn`, `drift-summit`, … |
| `C/C++ header` | 13 | `cobalt-marlin`, `drift-wharf`, `flint-anchor`, `granite-beacon`, … |
| `Go` | 11 | `bracket-cable`, `bracket-harbor`, `capstan-quay`, `cistern-cleat`, … |
| `R` | 11 | `basalt-mantle`, `basalt-quill`, `bracken-river`, `gale-meridian`, … |
| `Fortran` | 10 | `capstan-bollard`, `cedar-beacon`, `chainplate-ebb`, `clew-bulkhead`, … |
| `C/C++ (LLVM)` | 8 | `calm-hearth`, `cedar-canyon`, `elm-yonder`, `granite-beacon`, … |
| `Java (Maven)` | 7 | `ballast-mooring`, `calm-canyon`, `chainplate-berm`, `cistern-gauge`, … |
| `SQL` | 7 | `flint-terrace`, `keelson-berth`, `keelson-buoy`, `pumice-berth`, … |
| `Protocol Buffers` | 6 | `calm-canyon`, `elm-ridge`, `elm-summit`, `larch-fathom`, … |
| `Cython` | 5 | `basalt-mantle`, `gale-latch`, `moss-latch`, `onyx-ember`, … |
| `Coq` | 4 | `dune-mantle`, `v1-skill-ocaml-coq-toolchain`, `willow-wharf`, `zephyr-summit` |
| `assembly` | 3 | `flint-anchor`, `v1-item-042-hard`, `v1-item-042-main` |
| `TypeScript` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-compass` |
| `Verilog` | 3 | `marrow-vault`, `willow-wharf`, `zephyr-summit` |
| `Objective-C/MATLAB` | 2 | `cedar-beacon`, `umber-gasket` |
| `TeX` | 2 | `alder-crest`, `v1-item-052-main` |
| `CSS` | 1 | `stanchion-compass` |
| `Lean` | 1 | `calm-canyon` |
| `OCaml` | 1 | `v1-skill-ocaml-coq-toolchain` |
| `Scala` | 1 | `zephyr-summit` |

## Upstream repositories cloned at image-build time

77 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `github.com/BurntSushi/ripgrep` | 7 | `alewife-anchorage`, `ballast-anchorage`, `bosun-fathom`, `capstan-deepwater`, … |
| `github.com/duckdb/duckdb` | 6 | `ballast-deepwater`, `berm-coaming`, `brackish-deepwater`, `capstan-longshore`, … |
| `github.com/falconry/falcon` | 6 | `bracket-bridge`, `bulwark-chartroom`, `cistern-channel`, `corbel-stave`, … |
| `github.com/scipy/scipy` | 6 | `capstan-bollard`, `chainplate-ebb`, `clew-bulkhead`, `crance-bell`, … |
| `github.com/matplotlib/matplotlib` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `github.com/networkx/networkx` | 5 | `ballast-overtake`, `caulk-ebb`, `chainplate-bollard`, `lazaret-careen`, … |
| `github.com/nltk/nltk` | 5 | `ballast-pilot`, `chain-companion`, `chainplate-boom`, `lighter-boom`, … |
| `github.com/psf/requests` | 5 | `bracket-ember`, `cistern-flood`, `cockboat-caboose`, `midships-spinnaker`, … |
| `github.com/python-poetry/poetry` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `github.com/python-poetry/poetry-core` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `github.com/python/mypy` | 5 | `ballast-rudder`, `chainplate-current`, `companion-flint`, `painter-ebb`, … |
| `github.com/actions/go-versions` | 4 | `ballast-chartroom`, `capstan-inlet`, `dory-reach`, `shroud-bulkhead` |
| `github.com/adoptium/temurin25-binaries` | 4 | `bracket-cairn`, `cistern-compass`, `hoy-moor`, `nock-trestle` |
| `github.com/aquasecurity/trivy` | 4 | `ballast-chartroom`, `capstan-inlet`, `dory-reach`, `shroud-bulkhead` |
| `github.com/cure53/DOMPurify` | 4 | `bracket-beacon`, `cistern-bridge`, `fender-hull`, `plinth-wicket` |
| `github.com/encode/httpx` | 4 | `bracket-berth`, `cistern-cable`, `clinker-mast`, `forecastle-current` |
| `github.com/expressjs/express` | 4 | `bracket-bight`, `cistern-cairn`, `gaff-gate`, `sill-ember` |
| `github.com/giampaolo/psutil` | 4 | `bracket-buoy`, `cistern-cinder`, `garboard-yard`, `spile-wharf` |
| `github.com/gin-gonic/gin` | 4 | `bracket-cable`, `cistern-cleat`, `gasket-wake`, `spindrift-trim` |
| `github.com/git/git` | 4 | `ballast-fathom`, `capstan-pilot`, `gunwale-tideway`, `stay-strait` |
| `github.com/google/guava` | 4 | `ballast-hull`, `capstan-reach`, `hawse-shallows`, `stem-sloop` |
| `github.com/libvips/libvips` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `github.com/mikf/gallery-dl` | 4 | `bracket-cinder`, `cistern-crest`, `derrick-tarn`, `kedge-fairway` |
| `github.com/pallets/click` | 4 | `bracket-cleat`, `cistern-dune`, `corbel-weir`, `lighter-gate` |
| `github.com/pallets/werkzeug` | 4 | `bracket-coral`, `cistern-fathom`, `luff-yard`, `thole-ground` |
| `github.com/prettier/prettier` | 4 | `bracket-crest`, `cistern-ferry`, `marlinespike-wake`, `tiller-fathom` |
| `github.com/prometheus/prometheus` | 4 | `bracket-dune`, `cistern-flint`, `masthead-tideway`, `topsail-deepwater` |
| `github.com/PyCQA/bandit` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `github.com/pypa/setuptools` | 4 | `ballast-reach`, `chainplate-caboose`, `oakum-landfall`, `trawler-bowsprit` |
| `github.com/pytorch/vision` | 4 | `capstan-anchorage`, `chainplate-deepwater`, `palliser-companion`, `wale-beacon` |
| `github.com/redis/redis` | 4 | `bracket-flood`, `conduit-basin`, `hasp-plumb`, `pennant-caboose` |
| `github.com/scikit-image/scikit-image` | 4 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `github.com/semgrep/semgrep` | 4 | `capstan-boom`, `chainplate-fathom`, `poop-wheel`, `yard-sloop` |
| `github.com/sqlalchemy/sqlalchemy` | 4 | `cistern-basin`, `crojack-wheel`, `reef-sail`, `yawl-offing` |
| `github.com/sympy/sympy` | 4 | `bitts-longshore`, `cistern-beacon`, `clinker-quay`, `scantling-keel` |
| `github.com/syncthing/syncthing` | 4 | `bollard-inlet`, `capstan-current`, `chainplate-keel`, `scupper-gulf` |
| `github.com/tmux/tmux` | 4 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `sennit-foresheet` |
| `github.com/adoptium/temurin24-binaries` | 3 | `bracket-cairn`, `cistern-compass`, `hoy-moor` |
| `github.com/aio-libs/aiohttp` | 3 | `bracket-anchor`, `cistern-berth`, `cuddy-stem` |
| `github.com/apache/commons-lang` | 3 | `ballast-caboose`, `capstan-hull`, `deadwood-shoal` |
| `github.com/astral-sh/uv` | 3 | `ballast-current`, `capstan-keel`, `dragger-narrows` |
| `github.com/clap-rs/clap` | 3 | `bracket-basin`, `cistern-bight`, `dunnage-light` |
| `github.com/curl/curl` | 3 | `bracket-bell`, `cistern-buoy`, `figurehead-grapnel` |
| `github.com/gohugoio/hugo` | 3 | `ballast-foresheet`, `capstan-quay`, `halyard-spinnaker` |
| `github.com/jestjs/jest` | 3 | `capstan-roadstead`, `hawser-quay`, `stern-roadstead` |
| `github.com/junit-team/junit5` | 3 | `bracket-cairn`, `cistern-compass`, `hoy-moor` |
| `github.com/librosa/librosa` | 3 | `ballast-keel`, `capstan-rudder`, `jackstay-larboard` |
| `github.com/Mbed-TLS/mbedtls` | 3 | `alewife-dune`, `ballast-berm`, `capstan-drift` |
| `github.com/netty/netty` | 3 | `ballast-mooring`, `chainplate-berm`, `kelson-current` |
| `github.com/pallets/jinja` | 3 | `bracket-compass`, `cistern-ember`, `limber-cinder` |
| `github.com/psycopg/psycopg` | 3 | `bracket-fathom`, `cistern-forge`, `mizzen-seaboard` |
| `github.com/PyCQA/flake8` | 3 | `ballast-boom`, `capstan-fathom`, `chandlery-waypoint` |
| `github.com/pylint-dev/pylint` | 3 | `ballast-quay`, `chainplate-brackish`, `mooring-port` |
| `github.com/pypa/pip` | 3 | `bracket-ferry`, `cistern-gate`, `nock-meridian` |
| `github.com/pytest-dev/pytest` | 3 | `bracket-flint`, `conduit-anchor`, `oarlock-haven` |
| `github.com/rust-lang/regex` | 3 | `bracket-forge`, `pintle-berm`, `waterway-wharf` |
| `github.com/sharkdp/fd` | 3 | `capstan-brackish`, `chainplate-foresheet`, `quoin-swell` |
| `github.com/spf13/cobra` | 3 | `cistern-anchor`, `ratline-sound`, `yaw-roadstead` |
| `github.com/starship/starship` | 3 | `capstan-caboose`, `chainplate-hull`, `ropewalk-passage` |
| `github.com/statsmodels/statsmodels` | 3 | `capstan-chartroom`, `chainplate-inlet`, `rudder-main` |
| `github.com/Z3Prover/z3` | 3 | `ballast-brackish`, `capstan-foresheet`, `corvette-towpath` |
| `github.com/eslint/eslint` | 2 | `ballast-drift`, `capstan-mooring` |
| `github.com/explosion/spaCy` | 2 | `capstan-overtake`, `gaff-boom` |
| `github.com/serde-rs/serde` | 2 | `bracket-gate`, `portlight-trough` |
| `github.com/angr/angr` | 1 | `trunnel-reach` |
| `github.com/apache/kafka` | 1 | `mizzen-summit` |
| `github.com/arminbiere/cadical` | 1 | `ferrule-berth` |
| `github.com/id-Software/DOOM` | 1 | `ingot-flood` |
| `github.com/nothings/stb` | 1 | `jerkin-cleat` |
| `github.com/official-stockfish/Stockfish` | 1 | `pawl-bell` |
| `github.com/python/cpython` | 1 | `chainplate-caboose` |
| `github.com/qutip/qutip` | 1 | `tenon-orbit` |
| `github.com/RaRe-Technologies/gensim` | 1 | `quoin-vellum` |
| `github.com/shadow-maint/shadow` | 1 | `reeve-gate` |
| `github.com/TinyCC/tinycc` | 1 | `ferrule-keel` |
| `github.com/trinodb/trino` | 1 | `nock-trestle` |
| `github.com/yt-project/yt` | 1 | `turret-moor` |

## Services and datastores a task starts and drives

10 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `SQLite` | 36 | `bracket-moor`, `brine-cipher`, `calm-bridge`, `capstan-ebb`, … |
| `PostgreSQL` | 15 | `birch-bight`, `bracket-fathom`, `cistern-forge`, `dunlin-shoal`, … |
| `DuckDB` | 7 | `ballast-deepwater`, `berm-coaming`, `brackish-deepwater`, `capstan-longshore`, … |
| `nginx` | 7 | `gale-fathom`, `tundra-bridge`, `v1-item-034-hard`, `v1-item-034-main`, … |
| `Prometheus` | 6 | `bracket-dune`, `cistern-flint`, `halyard-bell`, `halyard-spire`, … |
| `Redis` | 6 | `bracket-flood`, `conduit-basin`, `hasp-plumb`, `hoy-moor`, … |
| `MariaDB` | 1 | `wale-ferry` |
| `MQTT (mosquitto)` | 1 | `juniper-notch` |
| `MySQL` | 1 | `wale-ferry` |
| `Terraform` | 1 | `escutcheon-stack` |

## Build systems

9 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `pyproject (PEP 517/518)` | 19 | `aster-vellum`, `bracket-moor`, `bracket-quay`, `fen-lantern`, … |
| `Make` | 13 | `calm-hearth`, `cobalt-marlin`, `drift-wharf`, `harbor-notch`, … |
| `setuptools` | 8 | `basalt-mantle`, `ember-wheel`, `gale-latch`, `harbor-gasket`, … |
| `npm` | 7 | `drift-dial`, `marline-tiller`, `marline-trough`, `scupper-lock`, … |
| `Cargo` | 5 | `conduit-vane`, `granite-beacon`, `lintel-flood`, `lintel-winch`, … |
| `tsc` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-compass` |
| `CMake` | 2 | `brine-ridge`, `granite-beacon` |
| `Go modules` | 2 | `escutcheon-cable`, `flume-oar` |
| `Maven` | 2 | `keelson-berth`, `redoubt-gate` |

## Base images

5 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `bench-base:python-3.12` | 782 | `alder-crest`, `alder-fathom`, `amber-braid`, `amber-cistern`, … |
| `bench-base:ubuntu-24.04` | 254 | `alewife-anchorage`, `alewife-dune`, `amber-upland`, `arid-hearth`, … |
| `bench-base:node-22` | 38 | `amber-ledge`, `ashen-lattice`, `ballast-drift`, `bracket-beacon`, … |
| `golang:1.26.3@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a` | 1 | `scupper-gulf` |
| `texlive/texlive` | 1 | `v1-item-052-main` |

## Python packages (pip)

287 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `numpy` (2.5.2, 2.5.3) | 166 | `alder-fathom`, `amber-dial`, `amber-helix`, `arid-cipher`, … |
| `pytest` (9.1.1) | 136 | `ballast-boom`, `ballast-longshore`, `ballast-overtake`, `ballast-pilot`, … |
| `setuptools` (84.0.0) | 57 | `aster-vellum`, `ballast-bollard`, `ballast-boom`, `ballast-keel`, … |
| `torch` (2.14.0, 2.14.0+cpu) | 48 | `alder-fathom`, `amber-dial`, `aspen-drift`, `brisk-wharf`, … |
| `scipy` (1.18.1) | 43 | `amber-helix`, `ballast-keel`, `ballast-overtake`, `basalt-quill`, … |
| `pandas` (3.0.5) | 40 | `amber-helix`, `arid-cipher`, `arid-yonder`, `aspen-drift`, … |
| `wheel` (0.48.0) | 32 | `aster-vellum`, `ballast-bollard`, `ballast-boom`, `ballast-keel`, … |
| `pytest-xdist` | 29 | `ballast-quay`, `ballast-roadstead`, `ballast-rudder`, `bracket-buoy`, … |
| `packaging` | 25 | `ballast-longshore`, `ballast-roadstead`, `bracket-ferry`, `bracket-flint`, … |
| `requests` (2.34.2) | 21 | `ballast-quay`, `ballast-roadstead`, `bracket-flint`, `calm-jetty`, … |
| `meson-python` | 18 | `ballast-longshore`, `capstan-berm`, `capstan-bollard`, `capstan-chartroom`, … |
| `ninja` | 18 | `ballast-longshore`, `capstan-berm`, `capstan-bollard`, `capstan-chartroom`, … |
| `pillow` (12.3.0) | 18 | `arid-orchid`, `ballast-longshore`, `brisk-anchor`, `capstan-berm`, … |
| `scikit-learn` (1.9.0) | 18 | `amber-helix`, `brisk-anchor`, `cedar-pier`, `cobalt-tide`, … |
| `flask` (3.1.3) | 17 | `amber-dial`, `amber-engine`, `amber-orchid`, `cypress-lantern`, … |
| `pytest-timeout` | 16 | `ballast-quay`, `bracket-anchor`, `bracket-compass`, `capstan-bollard`, … |
| `cython` (3.3.0) | 14 | `capstan-bollard`, `capstan-chartroom`, `cedar-beacon`, `chainplate-inlet`, … |
| `hypothesis` | 14 | `bitts-longshore`, `bracket-flint`, `capstan-bollard`, `capstan-overtake`, … |
| `meson` | 14 | `ballast-longshore`, `capstan-bollard`, `capstan-chartroom`, `capstan-cleat`, … |
| `transformers` (5.16.1) | 14 | `crisp-relay`, `ember-atlas`, `fern-engine`, `frost-quay`, … |
| `coverage` | 13 | `ballast-quay`, `ballast-reach`, `barge-basin`, `bracket-anchor`, … |
| `pyyaml` (6.0.3) | 13 | `ballast-pilot`, `cedar-cipher`, `chain-companion`, `chainplate-boom`, … |
| `certifi` | 11 | `ballast-longshore`, `bracket-ember`, `capstan-cleat`, `chainplate-anchorage`, … |
| `joblib` (1.6.0) | 11 | `ballast-pilot`, `capstan-rudder`, `cedar-pier`, `chain-companion`, … |
| `pooch` | 11 | `capstan-berm`, `capstan-bollard`, `capstan-rudder`, `chainplate-drift`, … |
| `pybind11` | 11 | `ballast-longshore`, `capstan-bollard`, `capstan-cleat`, `chainplate-anchorage`, … |
| `pytest-mock` | 11 | `ballast-pilot`, `ballast-roadstead`, `chain-companion`, `chainplate-boom`, … |
| `grpcio-tools` (1.83.1) | 10 | `calm-canyon`, `elm-ridge`, `elm-summit`, `juniper-wharf`, … |
| `pytest-cov` | 10 | `ballast-quay`, `capstan-berm`, `caulk-ebb`, `chainplate-brackish`, … |
| `pythran` | 10 | `capstan-berm`, `capstan-bollard`, `chainplate-drift`, `chainplate-ebb`, … |
| `build` (1.6.0) | 9 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `corbel-weir`, … |
| `grpcio` (1.83.1) | 9 | `calm-canyon`, `elm-ridge`, `elm-summit`, `juniper-wharf`, … |
| `virtualenv` | 9 | `ballast-roadstead`, `bracket-ferry`, `chainplate-chartroom`, `cistern-gate`, … |
| `cryptography` | 8 | `bracket-berth`, `cistern-cable`, `clinker-mast`, `forecastle-current`, … |
| `Cython` | 8 | `capstan-berm`, `chainplate-drift`, `chainplate-ebb`, `crance-bell`, … |
| `installer` | 8 | `ballast-roadstead`, `bracket-ferry`, `chainplate-chartroom`, `cistern-gate`, … |
| `mpmath` | 8 | `bitts-longshore`, `capstan-bollard`, `clew-bulkhead`, `clinker-quay`, … |
| `platformdirs` | 8 | `ballast-roadstead`, `bracket-ferry`, `chainplate-chartroom`, `companion-berm`, … |
| `protobuf` (7.36.1) | 8 | `calm-canyon`, `elm-ridge`, `juniper-wharf`, `larch-fathom`, … |
| `PyYAML` | 8 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `gaff-boom`, … |
| `click` | 7 | `ballast-pilot`, `capstan-overtake`, `chain-companion`, `chainplate-boom`, … |
| `python-dateutil` (2.9.0.post0) | 7 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `granite-grove`, … |
| `tqdm` | 7 | `ballast-pilot`, `chain-companion`, `chainplate-boom`, `gaff-boom`, … |
| `typing-extensions` | 7 | `ballast-quay`, `bracket-fathom`, `chainplate-brackish`, `cistern-basin`, … |
| `typing_extensions` | 7 | `ballast-rudder`, `capstan-rudder`, `chainplate-current`, `companion-flint`, … |
| `idna` | 6 | `bracket-ember`, `cistern-flood`, `cockboat-caboose`, `gaff-boom`, … |
| `iniconfig` | 6 | `bracket-ferry`, `bracket-flint`, `conduit-anchor`, `gaff-boom`, … |
| `MarkupSafe` | 6 | `bracket-compass`, `bracket-coral`, `cistern-ember`, `cistern-fathom`, … |
| `pathspec` | 6 | `ballast-rudder`, `chainplate-current`, `companion-flint`, `gaff-boom`, … |
| `pluggy` | 6 | `bracket-ferry`, `bracket-flint`, `conduit-anchor`, `gaff-boom`, … |
| `pyarrow` (25.0.1) | 6 | `drift-quarry`, `gale-jetty`, `juniper-wharf`, `umber-ridge`, … |
| `pygments` | 6 | `bracket-ferry`, `bracket-flint`, `conduit-anchor`, `nock-meridian`, … |
| `setuptools-scm` | 6 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `conduit-anchor`, … |
| `shellingham` | 6 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `gaff-boom`, … |
| `tokenizers` (0.23.2) | 6 | `flint-cipher`, `prism-hearth`, `raven-mantle`, `v1-item-016-hard`, … |
| `trio` | 6 | `bracket-berth`, `bracket-compass`, `cistern-cable`, `cistern-ember`, … |
| `urllib3` | 6 | `bracket-ember`, `cistern-flood`, `cockboat-caboose`, `gaff-boom`, … |
| `ast-serialize` | 5 | `ballast-rudder`, `chainplate-current`, `companion-flint`, `painter-ebb`, … |
| `attrs` | 5 | `bracket-flint`, `companion-flint`, `conduit-anchor`, `oarlock-haven`, … |
| `beautifulsoup4` (4.15.0) | 5 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `flint-orchid`, … |
| `cachecontrol` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `charset_normalizer` | 5 | `bracket-ember`, `cistern-flood`, `cockboat-caboose`, `midships-spinnaker`, … |
| `cleo` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `contourpy` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `cycler` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `deepdiff` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `defusedxml` | 5 | `ballast-pilot`, `chain-companion`, `chainplate-boom`, `lighter-boom`, … |
| `dulwich` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `fastjsonschema` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `findpython` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `fonttools` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `keyring` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `kiwisolver` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `librt` | 5 | `ballast-rudder`, `chainplate-current`, `companion-flint`, `painter-ebb`, … |
| `lxml` | 5 | `ballast-rudder`, `chainplate-current`, `companion-flint`, `painter-ebb`, … |
| `matplotlib` (3.11.1) | 5 | `gale-bridge`, `jackstay-larboard`, `pintle-flint`, `turret-moor`, … |
| `mypy_extensions` | 5 | `ballast-rudder`, `companion-flint`, `gaff-boom`, `painter-ebb`, … |
| `networkx` | 5 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `vine-terrace`, … |
| `pbr` | 5 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `gaff-boom`, … |
| `pbs-installer` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `pkginfo` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `poetry-core` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `pyparsing` | 5 | `ballast-longshore`, `capstan-cleat`, `chainplate-anchorage`, `jib-gangplank`, … |
| `pyproject-hooks` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `PySocks` | 5 | `bracket-ember`, `cistern-flood`, `cockboat-caboose`, `midships-spinnaker`, … |
| `pytest-asyncio` | 5 | `bracket-anchor`, `bracket-berth`, `cistern-berth`, `clinker-mast`, … |
| `rdflib` (7.6.0) | 5 | `flint-orchid`, `sage-keystone`, `v1-item-068-hard`, `v1-skill-rdf-engine`, … |
| `regex` | 5 | `ballast-pilot`, `chain-companion`, `chainplate-boom`, `lighter-boom`, … |
| `requests-toolbelt` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `responses` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `rich` | 5 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `gaff-boom`, … |
| `safetensors` (0.8.0) | 5 | `ember-atlas`, `fern-engine`, `gale-ridge`, `larch-cipher`, … |
| `tomlkit` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `trove-classifiers` | 5 | `ballast-roadstead`, `chainplate-chartroom`, `companion-berm`, `outrigger-ferry`, … |
| `werkzeug` | 5 | `bracket-ferry`, `cistern-gate`, `midships-spinnaker`, `nock-meridian`, … |
| `chardet` | 4 | `bracket-berth`, `cistern-cable`, `clinker-mast`, `forecastle-current` |
| `ephemeral-port-reserve` | 4 | `bracket-coral`, `cistern-fathom`, `luff-yard`, `thole-ground` |
| `fixtures` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `flit_core` | 4 | `cistern-fathom`, `corbel-weir`, `lighter-gate`, `luff-yard` |
| `GitPython` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `huggingface_hub` (1.30.0) | 4 | `ember-atlas`, `quartz-dial`, `v1-item-016-hard`, `v1-item-016-main` |
| `ipykernel` (7.3.0) | 4 | `basalt-mantle`, `gale-bridge`, `gale-meridian`, `olive-quarry` |
| `mccabe` | 4 | `ballast-boom`, `capstan-fathom`, `chandlery-waypoint`, `gaff-boom` |
| `mock` | 4 | `bracket-flint`, `conduit-anchor`, `gaff-boom`, `oarlock-haven` |
| `notebook` (7.6.2) | 4 | `elm-ridge`, `pale-heron`, `wick-lantern`, `willow-bridge` |
| `numpydoc` | 4 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `opencv-python-headless` (5.0.0.93) | 4 | `flint-fathom`, `iris-anchor`, `juniper-bridge`, `prism-ledge` |
| `pycodestyle` | 4 | `ballast-boom`, `capstan-fathom`, `chandlery-waypoint`, `gaff-boom` |
| `pyflakes` | 4 | `ballast-boom`, `capstan-fathom`, `chandlery-waypoint`, `gaff-boom` |
| `pytesseract` (0.3.13) | 4 | `ivory-kiln`, `juniper-bridge`, `prism-ledge`, `v1-item-025-hard` |
| `pytest-doctestplus` | 4 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `pytest-faulthandler` | 4 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `pytest-instafail` | 4 | `bracket-buoy`, `cistern-cinder`, `garboard-yard`, `spile-wharf` |
| `pytest-localserver` | 4 | `capstan-berm`, `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `pytest-xprocess` | 4 | `bracket-coral`, `cistern-fathom`, `luff-yard`, `thole-ground` |
| `setuptools_scm` | 4 | `capstan-chartroom`, `chainplate-inlet`, `oarlock-haven`, `rudder-main` |
| `six` | 4 | `ballast-quay`, `chainplate-brackish`, `gaff-boom`, `mooring-port` |
| `stevedore` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `testscenarios` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `testtools` | 4 | `ballast-bollard`, `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `tifffile` (2026.8.23) | 4 | `capstan-berm`, `pintle-flint`, `raven-orchid`, `wherry-trim` |
| `torchvision` | 4 | `capstan-anchorage`, `chainplate-deepwater`, `palliser-companion`, `wale-beacon` |
| `triton` | 4 | `elm-terrace`, `harbor-mantle`, `marble-ridge`, `moss-kernel` |
| `trustme` | 4 | `bracket-berth`, `cistern-cable`, `clinker-mast`, `forecastle-current` |
| `uvicorn` | 4 | `bracket-berth`, `cistern-cable`, `clinker-mast`, `forecastle-current` |
| `anyio` | 3 | `bracket-berth`, `clinker-mast`, `forecastle-current` |
| `argcomplete` | 3 | `bracket-flint`, `conduit-anchor`, `oarlock-haven` |
| `astroid` | 3 | `ballast-quay`, `chainplate-brackish`, `mooring-port` |
| `asv` | 3 | `chainplate-drift`, `pintle-flint`, `wherry-trim` |
| `biopython` (1.88) | 3 | `amber-helix`, `v1-item-021-main`, `v1-skill-biopython` |
| `brotli` | 3 | `bracket-berth`, `clinker-mast`, `forecastle-current` |
| `datasets` (5.0.1) | 3 | `v1-item-016-hard`, `v1-item-016-main`, `vine-yonder` |
| `decorator` | 3 | `capstan-rudder`, `jackstay-larboard`, `midships-spinnaker` |
| `distlib` | 3 | `bracket-ferry`, `gaff-boom`, `nock-meridian` |
| `filelock` | 3 | `bracket-ferry`, `gaff-boom`, `nock-meridian` |
| `formulaic` | 3 | `capstan-chartroom`, `chainplate-inlet`, `rudder-main` |
| `freezegun` | 3 | `bracket-anchor`, `cistern-berth`, `cuddy-stem` |
| `greenlet` | 3 | `cistern-basin`, `reef-sail`, `yawl-offing` |
| `h2` | 3 | `bracket-berth`, `clinker-mast`, `forecastle-current` |
| `hydra-core` (1.3.6) | 3 | `cedar-pier`, `cinder-vane`, `drift-terrace` |
| `imageio` | 3 | `capstan-berm`, `pintle-flint`, `wherry-trim` |
| `ipython` (9.17.1) | 3 | `capstan-overtake`, `gale-ledge`, `larch-dial` |
| `jschema-to-python` | 3 | `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `lazy-loader` | 3 | `capstan-berm`, `pintle-flint`, `wherry-trim` |
| `lazy_loader` | 3 | `capstan-rudder`, `chainplate-drift`, `jackstay-larboard` |
| `markupsafe` | 3 | `bracket-ferry`, `midships-spinnaker`, `nock-meridian` |
| `numba` | 3 | `ballast-keel`, `capstan-rudder`, `jackstay-larboard` |
| `patsy` | 3 | `capstan-chartroom`, `chainplate-inlet`, `rudder-main` |
| `psycopg2-binary` | 3 | `birch-bight`, `granary-ledge`, `moor-atlas` |
| `py` | 3 | `ballast-quay`, `chainplate-brackish`, `mooring-port` |
| `pytest-aiohttp` | 3 | `bracket-anchor`, `cistern-berth`, `cuddy-stem` |
| `pytest-benchmark` | 3 | `ballast-quay`, `chainplate-brackish`, `mooring-port` |
| `python-chess` (1.999) | 3 | `umber-gasket`, `v1-item-009-main`, `v1-skill-chess-move-generation` |
| `python-discovery` | 3 | `bracket-ferry`, `gaff-boom`, `nock-meridian` |
| `pyvips` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `rdkit` (2026.3.6) | 3 | `cedar-gasket`, `drift-atlas`, `zephyr-anchor` |
| `sarif-om` | 3 | `barge-basin`, `capstan-ebb`, `sheet-coaming` |
| `scripttest` | 3 | `bracket-ferry`, `cistern-gate`, `nock-meridian` |
| `sympy` (1.14.0) | 3 | `basalt-quill`, `cedar-jetty`, `quartz-delta` |
| `tomli` (2.4.1) | 3 | `ballast-rudder`, `onyx-upland`, `vine-pier` |
| `vosk` (0.3.45) | 3 | `raven-orchid`, `zephyr-cipher`, `zephyr-orchid` |
| `xmlschema` | 3 | `bracket-flint`, `conduit-anchor`, `oarlock-haven` |
| `astropy` (8.0.1) | 2 | `basalt-quill`, `iris-terrace` |
| `boto3` (1.43.89) | 2 | `brisk-wharf`, `juniper-wharf` |
| `cffi` | 2 | `luff-yard`, `thole-ground` |
| `highspy` (1.15.1) | 2 | `umber-terrace`, `zephyr-forge` |
| `ics` (0.7.3) | 2 | `granite-grove`, `iris-ember` |
| `jinja2` | 2 | `ballast-berm`, `juniper-ledge` |
| `jupyter` (1.1.1) | 2 | `basalt-mantle`, `olive-quarry` |
| `mlflow` (3.16.0) | 2 | `elm-summit`, `gale-ridge` |
| `msgpack` | 2 | `capstan-rudder`, `jackstay-larboard` |
| `mujoco` (3.12.0) | 2 | `drift-atlas`, `iris-anchor` |
| `nbclient` (0.11.0) | 2 | `gale-bridge`, `gale-meridian` |
| `nbformat` (5.11.1) | 2 | `gale-bridge`, `gale-meridian` |
| `openpyxl` (3.1.5) | 2 | `elm-keystone`, `flint-ember` |
| `playwright` (1.62.0) | 2 | `amber-orchid`, `gale-vault` |
| `pulp` (3.3.2) | 2 | `umber-terrace`, `zephyr-forge` |
| `pypdf` (6.18.0) | 2 | `flint-orchid`, `sage-keystone` |
| `pypiserver` (2.4.1) | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `pytest-httpbin` | 2 | `midships-spinnaker`, `transom-chartroom` |
| `pytest-socket` | 2 | `bracket-ferry`, `nock-meridian` |
| `sortedcontainers` | 2 | `gaff-boom`, `oarlock-haven` |
| `soundfile` (0.14.0) | 2 | `jackstay-larboard`, `zephyr-cipher` |
| `stestr` | 2 | `barge-basin`, `sheet-coaming` |
| `towncrier` | 2 | `ballast-quay`, `mooring-port` |
| `watchdog` | 2 | `luff-yard`, `thole-ground` |
| `zstandard` | 2 | `bracket-berth`, `clinker-mast` |
| `16` | 1 | `chainplate-ebb` |
| `aiohttp` (3.14.3) | 1 | `juniper-notch` |
| `annotated-doc` | 1 | `gaff-boom` |
| `annotated-types` | 1 | `gaff-boom` |
| `autograd` (1.9.1) | 1 | `v1-skill-autograd` |
| `awscli` (1.46.1) | 1 | `brisk-wharf` |
| `black` | 1 | `gaff-boom` |
| `blis` | 1 | `gaff-boom` |
| `bottle` (0.13.4) | 1 | `v1-item-026-main` |
| `catalogue` | 1 | `gaff-boom` |
| `cfgv` | 1 | `gaff-boom` |
| `charset-normalizer` | 1 | `gaff-boom` |
| `cloudpathlib` | 1 | `gaff-boom` |
| `cloudpickle` | 1 | `gaff-boom` |
| `cmyt` | 1 | `turret-moor` |
| `colorama` | 1 | `ballast-bollard` |
| `confection` | 1 | `gaff-boom` |
| `coreclutch` | 1 | `vine-inlet` |
| `cymem` | 1 | `gaff-boom` |
| `cython-lint` | 1 | `gaff-boom` |
| `duckdb` | 1 | `wale-reef` |
| `ewah-bool-utils` | 1 | `turret-moor` |
| `execnet` | 1 | `oarlock-haven` |
| `fasttext-wheel` | 1 | `cobalt-sonar` |
| `flake8` | 1 | `gaff-boom` |
| `flit-core` | 1 | `cistern-gate` |
| `gensim` | 1 | `zephyr-bridge` |
| `identify` | 1 | `gaff-boom` |
| `isort` | 1 | `gaff-boom` |
| `itsdangerous` | 1 | `midships-spinnaker` |
| `jax` | 1 | `vine-terrace` |
| `jaxley` | 1 | `vine-terrace` |
| `jaxlib` | 1 | `vine-terrace` |
| `Jinja2` | 1 | `gaff-boom` |
| `jsonschema` | 1 | `ballast-berm` |
| `jupyter_client` (8.10.0) | 1 | `gale-meridian` |
| `jupyter_core` (5.9.1) | 1 | `gale-meridian` |
| `jupyter_server` | 1 | `quiet-loom` |
| `langdetect` (1.0.9) | 1 | `quartz-dial` |
| `lotusfields` | 1 | `vine-inlet` |
| `markdown-it-py` | 1 | `gaff-boom` |
| `mdurl` | 1 | `gaff-boom` |
| `ml_datasets` | 1 | `gaff-boom` |
| `more-itertools` | 1 | `turret-moor` |
| `moto` (5.2.3) | 1 | `brisk-wharf` |
| `murmurhash` | 1 | `gaff-boom` |
| `mypy` | 1 | `gaff-boom` |
| `mypy-extensions` | 1 | `chainplate-current` |
| `nbconvert` (7.17.1) | 1 | `gale-meridian` |
| `nodeenv` | 1 | `gaff-boom` |
| `ortools` (9.15.6755) | 1 | `umber-terrace` |
| `paho-mqtt` (2.1.0) | 1 | `juniper-notch` |
| `pexpect` | 1 | `oarlock-haven` |
| `pre_commit` | 1 | `gaff-boom` |
| `preshed` | 1 | `gaff-boom` |
| `prometheus-client` | 1 | `halyard-spire` |
| `psutil` | 1 | `painter-ebb` |
| `ptyprocess` | 1 | `oarlock-haven` |
| `pydantic` | 1 | `gaff-boom` |
| `pydantic_core` | 1 | `gaff-boom` |
| `Pygments` | 1 | `gaff-boom` |
| `pymupdf` (1.28.2) | 1 | `v1-item-025-hard` |
| `pyOpenSSL` | 1 | `juniper-wharf` |
| `pyspark` (4.2.0) | 1 | `vine-yonder` |
| `pystan` (3.10.1) | 1 | `juniper-pier` |
| `pytest-mpl` | 1 | `jackstay-larboard` |
| `pytest-ruff` | 1 | `trawler-bowsprit` |
| `pytest-snapshot` | 1 | `poop-wheel` |
| `pytokens` | 1 | `gaff-boom` |
| `redis` | 1 | `thwart-quarry` |
| `ridgedf` | 1 | `elm-ridge` |
| `ruff` | 1 | `trawler-bowsprit` |
| `sentence-transformers` (6.0.1) | 1 | `v1-item-048-main` |
| `smart_open` | 1 | `gaff-boom` |
| `socksio` | 1 | `forecastle-current` |
| `soxr` | 1 | `jackstay-larboard` |
| `spacy-legacy` | 1 | `gaff-boom` |
| `spacy-loggers` | 1 | `gaff-boom` |
| `srsly` | 1 | `gaff-boom` |
| `textnorm` | 1 | `crisp-relay` |
| `thinc` | 1 | `gaff-boom` |
| `timm` (1.0.29) | 1 | `prism-ledge` |
| `tinycss2` | 1 | `scupper-sail` |
| `tokenize_rt` | 1 | `gaff-boom` |
| `toksplit` | 1 | `crisp-relay` |
| `tomli-w` | 1 | `turret-moor` |
| `typer` | 1 | `gaff-boom` |
| `typer-slim` | 1 | `gaff-boom` |
| `types-mock` | 1 | `gaff-boom` |
| `types-requests` | 1 | `gaff-boom` |
| `types-setuptools` | 1 | `gaff-boom` |
| `typing-inspection` | 1 | `gaff-boom` |
| `tzdata` (2026.3) | 1 | `v1-skill-timezone-date-ranges` |
| `unyt` | 1 | `turret-moor` |
| `uv` (0.12.10) | 1 | `gale-fathom` |
| `wasabi` | 1 | `gaff-boom` |
| `wasmtime` (48.0.0) | 1 | `umber-engine` |
| `weasel` | 1 | `gaff-boom` |
| `wrapt` | 1 | `gaff-boom` |
| `z3-solver` (5.1.0.0) | 1 | `zephyr-summit` |

## JavaScript packages (npm)

36 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `2>&1` | 8 | `ballast-drift`, `capstan-mooring`, `capstan-roadstead`, `gaff-gate`, … |
| `>` | 7 | `ballast-drift`, `capstan-mooring`, `capstan-roadstead`, `hawser-quay`, … |
| `/tmp/npm-install.log` | 6 | `ballast-drift`, `capstan-mooring`, `capstan-roadstead`, `marlinespike-wake`, … |
| `OK` | 5 | `ballast-drift`, `capstan-mooring`, `marlinespike-wake`, `sill-ember`, … |
| `react` | 5 | `marline-tiller`, `scupper-lock`, `stanchion-bell`, `stanchion-compass`, … |
| `react-dom` | 5 | `marline-tiller`, `scupper-lock`, `stanchion-bell`, `stanchion-compass`, … |
| `jsdom` | 4 | `marline-tiller`, `scupper-lock`, `stanchion-bell`, `stanchion-compass` |
| `typescript` | 4 | `hawser-quay`, `marline-tiller`, `scupper-lock`, `stanchion-compass` |
| `@testing-library/dom` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-bell` |
| `@testing-library/react` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-bell` |
| `@types/react` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-compass` |
| `@types/react-dom` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-compass` |
| `vitest` | 3 | `marline-tiller`, `scupper-lock`, `stanchion-bell` |
| `@types/node` | 2 | `hawser-quay`, `marline-tiller` |
| `vite` | 2 | `marline-tiller`, `stanchion-compass` |
| `/tmp/npm-cache` | 1 | `marlinespike-wake` |
| `/tmp/npm.log` | 1 | `hawser-quay` |
| `>>` | 1 | `capstan-mooring` |
| `@aws-amplify/lambda` | 1 | `vine-inlet` |
| `@aws-sdk/client-s3` | 1 | `vine-inlet` |
| `@hedge/gauge-ribbon` | 1 | `vine-inlet` |
| `@hedge/rivette-core` | 1 | `vine-inlet` |
| `@jest/get-type` | 1 | `hawser-quay` |
| `@jest/types` | 1 | `hawser-quay` |
| `@testing-library/jest-dom` | 1 | `marline-tiller` |
| `@testing-library/user-event` | 1 | `scupper-lock` |
| `@vitejs/plugin-react` | 1 | `stanchion-compass` |
| `aws-amplify` | 1 | `vine-inlet` |
| `aws-sdk` | 1 | `vine-inlet` |
| `axe-core` | 1 | `stanchion-bell` |
| `espree` | 1 | `capstan-mooring` |
| `mocha` | 1 | `capstan-mooring` |
| `motif` | 1 | `drift-dial` |
| `pretty-format` | 1 | `hawser-quay` |
| `react-native` | 1 | `vine-inlet` |
| `sector-srv` | 1 | `drift-dial` |

## Rust crates (Cargo)

3 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `veldt-core` | 1 | `conduit-vane` |
| `veldt-measure` | 1 | `conduit-vane` |
| `veldt-transport` | 1 | `conduit-vane` |

## Go modules

2 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest` | 1 | `windlass-jetty` |
| `google.golang.org/protobuf/cmd/protoc-gen-go@latest` | 1 | `windlass-jetty` |

## Maven artifacts

13 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `junit-jupiter` | 2 | `keelson-berth`, `redoubt-gate` |
| `junit-platform-launcher` | 2 | `keelson-berth`, `redoubt-gate` |
| `maven-compiler-plugin` | 2 | `keelson-berth`, `redoubt-gate` |
| `maven-jar-plugin` | 2 | `keelson-berth`, `redoubt-gate` |
| `maven-surefire-plugin` | 2 | `keelson-berth`, `redoubt-gate` |
| `catalog-service` | 1 | `keelson-berth` |
| `conventions` | 1 | `redoubt-gate` |
| `formatter` | 1 | `redoubt-gate` |
| `greeter` | 1 | `redoubt-gate` |
| `lib-y` | 1 | `redoubt-gate` |
| `maven-enforcer-plugin` | 1 | `redoubt-gate` |
| `redoubt-gate` | 1 | `redoubt-gate` |
| `sqlite-jdbc` | 1 | `keelson-berth` |

## apt packages

226 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `ca-certificates` | 123 | `alewife-anchorage`, `amber-engine`, `anchor-quill`, `ballast-anchorage`, … |
| `git` | 111 | `alewife-anchorage`, `alewife-dune`, `ballast-anchorage`, `ballast-berm`, … |
| `build-essential` | 95 | `alewife-anchorage`, `alewife-dune`, `arid-orchid`, `ballast-anchorage`, … |
| `gcc` | 89 | `arid-orchid`, `ashen-vane`, `ballast-deepwater`, `basalt-cipher`, … |
| `python3` | 81 | `alewife-dune`, `amber-engine`, `amber-ledge`, `arid-hearth`, … |
| `curl` | 77 | `alewife-anchorage`, `amber-engine`, `ballast-anchorage`, `ballast-caboose`, … |
| `make` | 58 | `ashen-vane`, `ballast-berm`, `ballast-brackish`, `ballast-deepwater`, … |
| `libc6-dev` | 53 | `ashen-vane`, `bracket-buoy`, `cistern-cinder`, `dusk-lattice`, … |
| `pkg-config` | 40 | `alewife-anchorage`, `ballast-anchorage`, `ballast-current`, `ballast-longshore`, … |
| `g++` | 39 | `ballast-brackish`, `ballast-deepwater`, `basalt-cipher`, `berm-coaming`, … |
| `file` | 29 | `amber-upland`, `ashen-vane`, `ballast-fathom`, `basalt-bridge`, … |
| `procps` | 26 | `amber-engine`, `anchor-quill`, `birch-bight`, `bracket-flood`, … |
| `binutils` | 25 | `basalt-cipher`, `brine-mesa`, `brine-ridge`, `calm-hearth`, … |
| `openssl` | 23 | `bracket-bell`, `brisk-jetty`, `cistern-buoy`, `fern-terrace`, … |
| `ninja-build` | 17 | `ballast-deepwater`, `ballast-longshore`, `berm-coaming`, `bracket-channel`, … |
| `cmake` | 16 | `ballast-brackish`, `ballast-deepwater`, `basalt-cipher`, `berm-coaming`, … |
| `openjdk-21-jdk-headless` | 15 | `ballast-hull`, `ballast-mooring`, `bracket-cairn`, `capstan-reach`, … |
| `python3-pip` | 15 | `arid-orchid`, `bracket-channel`, `calm-canyon`, `cedar-canyon`, … |
| `libssl-dev` | 13 | `ballast-current`, `ballast-fathom`, `bracket-bell`, `brisk-wharf`, … |
| `postgresql` | 12 | `birch-bight`, `dunlin-shoal`, `granary-ledge`, `gull-wharf`, … |
| `postgresql-client` | 12 | `birch-bight`, `dunlin-shoal`, `granary-ledge`, `gull-wharf`, … |
| `coreutils` | 11 | `cinder-guest`, `granite-beacon`, `hasp-plumb`, `hollow-notch`, … |
| `gzip` | 11 | `basalt-bridge`, `brisk-jetty`, `cinder-guest`, `iris-ledge`, … |
| `gfortran` | 10 | `capstan-bollard`, `cedar-beacon`, `chainplate-ebb`, `clew-bulkhead`, … |
| `qemu-system-x86` | 10 | `amber-upland`, `basalt-bridge`, `brisk-jetty`, `cinder-guest`, … |
| `cpio` | 9 | `amber-upland`, `basalt-bridge`, `brisk-jetty`, `cinder-guest`, … |
| `iproute2` | 9 | `amber-upland`, `basalt-bridge`, `brisk-jetty`, `fern-terrace`, … |
| `python3-dev` | 9 | `basalt-mantle`, `bracket-channel`, `cistern-coral`, `ember-wheel`, … |
| `autoconf` | 8 | `boom-ground`, `bracket-bell`, `cistern-bell`, `cistern-buoy`, … |
| `automake` | 8 | `boom-ground`, `bracket-bell`, `cistern-bell`, `cistern-buoy`, … |
| `busybox-static` | 8 | `amber-upland`, `basalt-bridge`, `brisk-jetty`, `fern-terrace`, … |
| `clang` | 8 | `calm-hearth`, `cedar-canyon`, `elm-yonder`, `granite-beacon`, … |
| `libexpat1-dev` | 8 | `ballast-fathom`, `bracket-channel`, `capstan-pilot`, `cistern-coral`, … |
| `libtool` | 8 | `boom-ground`, `bracket-bell`, `cistern-bell`, `cistern-buoy`, … |
| `sudo` | 8 | `brisk-atlas`, `drift-summit`, `echo-mantle`, `hollow-notch`, … |
| `unzip` | 8 | `ballast-fathom`, `capstan-pilot`, `gunwale-tideway`, `hollow-ledge`, … |
| `vim` | 8 | `arid-jetty`, `dune-beacon`, `ember-latch`, `gale-bridge`, … |
| `zlib1g-dev` | 8 | `ballast-fathom`, `bracket-bell`, `capstan-pilot`, `cistern-buoy`, … |
| `gdb` | 7 | `bracket-bell`, `calm-hearth`, `cistern-buoy`, `moss-forge`, … |
| `golang-go` | 7 | `bracket-harbor`, `culvert-keel`, `culvert-mast`, `escutcheon-cable`, … |
| `jq` | 7 | `echo-mantle`, `gale-bridge`, `halyard-spire`, `hollow-fathom`, … |
| `maven` | 7 | `ballast-mooring`, `calm-canyon`, `chainplate-berm`, `cistern-gauge`, … |
| `openssh-server` | 7 | `drift-canyon`, `drift-summit`, `hollow-atlas`, `prism-anchor`, … |
| `patch` | 7 | `bracket-dune`, `cistern-anchor`, `figurehead-grapnel`, `hollow-keystone`, … |
| `zstd` | 7 | `basalt-bridge`, `basalt-cipher`, `brisk-jetty`, `dune-hearth`, … |
| `bison` | 6 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `gale-pier`, … |
| `cargo` | 6 | `conduit-vane`, `granite-beacon`, `lintel-flood`, `lintel-winch`, … |
| `findutils` | 6 | `drift-forge`, `kelp-fjord`, `larch-vane`, `nectar-helix`, … |
| `libzstd-dev` | 6 | `bracket-bell`, `bracket-channel`, `cistern-buoy`, `cistern-coral`, … |
| `linux-image-generic` | 6 | `amber-upland`, `basalt-bridge`, `brisk-jetty`, `fern-terrace`, … |
| `nginx` | 6 | `tundra-bridge`, `v1-item-034-hard`, `v1-item-034-main`, `v1-item-050-hard`, … |
| `openssh-client` | 6 | `brisk-jetty`, `drift-canyon`, `fern-terrace`, `hollow-atlas`, … |
| `postfix` | 6 | `anchor-quill`, `brisk-wharf`, `echo-mantle`, `hollow-notch`, … |
| `r-base` | 6 | `basalt-quill`, `sable-quill`, `tundra-jetty`, `v1-item-001-hard`, … |
| `rustc` | 6 | `conduit-vane`, `granite-beacon`, `lintel-flood`, `lintel-winch`, … |
| `tar` | 6 | `kelp-fjord`, `quartz-orchid`, `silt-barrow`, `umber-mantle`, … |
| `ffmpeg` | 5 | `flint-fathom`, `raven-orchid`, `v1-skill-ffmpeg-video-frames`, `zephyr-cipher`, … |
| `gettext` | 5 | `ballast-fathom`, `capstan-pilot`, `gunwale-tideway`, `reeve-gate`, … |
| `libblas3` | 5 | `capstan-bollard`, `clew-bulkhead`, `crance-bell`, `plimsoll-bell`, … |
| `liblapack3` | 5 | `capstan-bollard`, `clew-bulkhead`, `crance-bell`, `plimsoll-bell`, … |
| `libopenblas0-pthread` | 5 | `capstan-bollard`, `clew-bulkhead`, `crance-bell`, `plimsoll-bell`, … |
| `libpng-dev` | 5 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice`, … |
| `python3-venv` | 5 | `halyard-spire`, `harbor-gasket`, `nectar-helix`, `quartz-grove`, … |
| `r-base-core` | 5 | `basalt-mantle`, `bracken-river`, `gale-meridian`, `olive-quarry`, … |
| `strace` | 5 | `bracket-bell`, `cistern-buoy`, `figurehead-grapnel`, `reeve-gate`, … |
| `tesseract-ocr` | 5 | `brisk-anchor`, `ivory-kiln`, `juniper-bridge`, `prism-ledge`, … |
| `acl` | 4 | `brisk-atlas`, `kite-helix`, `meadow-bridge`, `prism-anchor` |
| `byacc` | 4 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `sennit-foresheet` |
| `coq` | 4 | `dune-mantle`, `v1-skill-ocaml-coq-toolchain`, `willow-wharf`, `zephyr-summit` |
| `gcc-mipsel-linux-gnu` | 4 | `kite-anchor`, `larch-terrace`, `v1-item-041-hard`, `v1-item-041-main` |
| `libc6-dev-mipsel-cross` | 4 | `kite-anchor`, `larch-terrace`, `v1-item-041-hard`, `v1-item-041-main` |
| `libcurl4-openssl-dev` | 4 | `ballast-fathom`, `capstan-pilot`, `gunwale-tideway`, `stay-strait` |
| `libevent-dev` | 4 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `sennit-foresheet` |
| `libfftw3-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `libglib2.0-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `libjpeg-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `liblcms2-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `libncurses-dev` | 4 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `sennit-foresheet` |
| `libtiff-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `libutempter-dev` | 4 | `boom-ground`, `cistern-bell`, `crosstrees-trough`, `sennit-foresheet` |
| `libwebp-dev` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `linux-libc-dev` | 4 | `bracket-buoy`, `cistern-cinder`, `garboard-yard`, `spile-wharf` |
| `man-db` | 4 | `kelp-fjord`, `umber-summit`, `wren-cipher`, `zephyr-notch` |
| `meson` | 4 | `bracket-channel`, `cistern-coral`, `jetsam-head`, `kedge-lattice` |
| `openjdk-17-jdk-headless` | 4 | `brisk-grove`, `calm-canyon`, `echo-mantle`, `hollow-notch` |
| `qemu-utils` | 4 | `basalt-bridge`, `brisk-jetty`, `iris-ledge`, `larch-hearth` |
| `r-cran-irkernel` | 4 | `basalt-mantle`, `gale-meridian`, `olive-quarry`, `tundra-jetty` |
| `r-cran-jsonlite` | 4 | `basalt-mantle`, `gale-meridian`, `tundra-jetty`, `wren-forge` |
| `sqlite3` | 4 | `flint-terrace`, `keelson-berth`, `pumice-berth`, `quay-ledger` |
| `sshpass` | 4 | `brisk-jetty`, `drift-canyon`, `fern-terrace`, `umber-yonder` |
| `valgrind` | 4 | `calm-hearth`, `cobalt-marlin`, `harbor-notch`, `hollow-keystone` |
| `dropbear` | 3 | `basalt-bridge`, `brisk-jetty`, `fern-terrace` |
| `genisoimage` | 3 | `fern-terrace`, `kite-helix`, `meadow-bridge` |
| `gnupg` | 3 | `kelp-fjord`, `umber-summit`, `wren-cipher` |
| `libbrotli-dev` | 3 | `bracket-bell`, `cistern-buoy`, `figurehead-grapnel` |
| `libbz2-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libexif-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libfontconfig1-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libgsf-1-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `liblzma-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libomp-dev` | 3 | `brine-mesa`, `cedar-canyon`, `kite-yonder` |
| `libopenjp2-7-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libopenmpi-dev` | 3 | `brisk-wharf`, `dune-hearth`, `prism-bridge` |
| `liborc-0.4-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libpango1.0-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libpq5` | 3 | `bracket-fathom`, `cistern-forge`, `mizzen-seaboard` |
| `libpsl-dev` | 3 | `bracket-bell`, `cistern-buoy`, `figurehead-grapnel` |
| `librsvg2-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `libxml2-dev` | 3 | `bracket-channel`, `cistern-coral`, `jetsam-head` |
| `llvm-18` | 3 | `dune-mantle`, `elm-yonder`, `wren-link` |
| `netcat-openbsd` | 3 | `bracket-flood`, `echo-mantle`, `hollow-notch` |
| `nodejs` | 3 | `arid-jetty`, `gale-fathom`, `vine-helix` |
| `openjdk-21-jdk` | 3 | `ballast-caboose`, `capstan-hull`, `deadwood-shoal` |
| `openmpi-bin` | 3 | `brisk-wharf`, `dune-hearth`, `prism-bridge` |
| `p7zip-full` | 3 | `quartz-orchid`, `vine-mantle`, `zephyr-engine` |
| `perl` | 3 | `alewife-dune`, `capstan-drift`, `figurehead-grapnel` |
| `psmisc` | 3 | `raven-orchid`, `v1-skill-port-process-management`, `yoke-inlet` |
| `tcl` | 3 | `bracket-flood`, `conduit-basin`, `pennant-caboose` |
| `tcl-dev` | 3 | `bracket-flood`, `conduit-basin`, `pennant-caboose` |
| `util-linux` | 3 | `cistern-anchor`, `fern-terrace`, `ratline-sound` |
| `xxd` | 3 | `arid-jetty`, `sage-wharf`, `umber-mantle` |
| `z3` | 3 | `dune-mantle`, `elm-yonder`, `zephyr-summit` |
| `flex` | 2 | `gale-pier`, `reeve-gate` |
| `fonts-dejavu-core` | 2 | `arid-orchid`, `brisk-anchor` |
| `gawk` | 2 | `gale-bridge`, `willow-bridge` |
| `gcc-mips-linux-gnu` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `grep` | 2 | `hollow-notch`, `umber-summit` |
| `john` | 2 | `vine-mantle`, `zephyr-engine` |
| `libc6-dev-mips-cross` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `libosmesa6` | 2 | `basalt-mantle`, `onyx-gasket` |
| `libpcre2-dev` | 2 | `gunwale-tideway`, `stay-strait` |
| `prometheus` | 2 | `halyard-bell`, `halyard-spire` |
| `python3-jinja2` | 2 | `alewife-dune`, `capstan-drift` |
| `python3-jsonschema` | 2 | `alewife-dune`, `capstan-drift` |
| `python3-pytest` | 2 | `halyard-bell`, `v1-item-001-hard` |
| `python3-z3` | 2 | `dune-mantle`, `elm-yonder` |
| `qemu-user` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `qemu-user-static` | 2 | `kite-anchor`, `larch-terrace` |
| `r-cran-rcpp` | 2 | `tundra-jetty`, `wren-forge` |
| `r-cran-rstan` | 2 | `tundra-jetty`, `wren-forge` |
| `sed` | 2 | `hollow-notch`, `umber-summit` |
| `tcpdump` | 2 | `echo-mantle`, `hollow-notch` |
| `whois` | 2 | `echo-mantle`, `hollow-notch` |
| `zip` | 2 | `kite-helix`, `meadow-bridge` |
| `zsh` | 2 | `gale-fathom`, `umber-anchor` |
| `autopoint` | 1 | `reeve-gate` |
| `bc` | 1 | `gale-pier` |
| `binutils-aarch64-linux-gnu` | 1 | `v1-skill-c-cross-compilation` |
| `bsdmainutils` | 1 | `v1-item-053-main` |
| `bubblewrap` | 1 | `granite-beacon` |
| `ca-certificates-java` | 1 | `cistern-gauge` |
| `clang-16` | 1 | `zephyr-summit` |
| `clang-18` | 1 | `dune-mantle` |
| `default-jdk` | 1 | `zephyr-summit` |
| `default-jdk-headless` | 1 | `vine-mantle` |
| `dosfstools` | 1 | `fern-terrace` |
| `dpkg` | 1 | `slate-hollow` |
| `e2fsprogs` | 1 | `fern-terrace` |
| `elan` | 1 | `calm-canyon` |
| `fdisk` | 1 | `fern-terrace` |
| `fonts-liberation` | 1 | `v1-item-025-hard` |
| `gcc-aarch64-linux-gnu` | 1 | `v1-skill-c-cross-compilation` |
| `gdisk` | 1 | `fern-terrace` |
| `gpg` | 1 | `gale-pier` |
| `groff-base` | 1 | `zephyr-notch` |
| `iputils-ping` | 1 | `fern-terrace` |
| `iverilog` | 1 | `marrow-vault` |
| `less` | 1 | `cistern-dune` |
| `libacl1-dev` | 1 | `reeve-gate` |
| `libattr1-dev` | 1 | `reeve-gate` |
| `libaudit-dev` | 1 | `reeve-gate` |
| `libcrypt-dev` | 1 | `reeve-gate` |
| `libelf-dev` | 1 | `gale-pier` |
| `libgl1-mesa-dev` | 1 | `arid-orchid` |
| `libgmp-dev` | 1 | `granite-beacon` |
| `libgomp1` | 1 | `gale-quarry` |
| `libnsl-dev` | 1 | `reeve-gate` |
| `libopenblas-dev` | 1 | `chainplate-ebb` |
| `libosmesa6-dev` | 1 | `arid-orchid` |
| `libpam0g` | 1 | `reeve-gate` |
| `libselinux1-dev` | 1 | `reeve-gate` |
| `libsqlite3-0` | 1 | `dune-beacon` |
| `libx11-dev` | 1 | `ingot-flood` |
| `libxext-dev` | 1 | `ingot-flood` |
| `libzmq5` | 1 | `gale-meridian` |
| `linux-source` | 1 | `gale-pier` |
| `lld` | 1 | `umber-engine` |
| `llvm` | 1 | `kite-yonder` |
| `llvm-16` | 1 | `zephyr-summit` |
| `llvm-18-tools` | 1 | `elm-yonder` |
| `lsof` | 1 | `v1-skill-port-process-management` |
| `mailutils` | 1 | `brisk-wharf` |
| `mariadb-client` | 1 | `wale-ferry` |
| `mariadb-server` | 1 | `wale-ferry` |
| `mesa-utils` | 1 | `arid-orchid` |
| `mlmmj` | 1 | `brisk-wharf` |
| `mosquitto` | 1 | `juniper-notch` |
| `net-tools` | 1 | `fern-terrace` |
| `npm` | 1 | `gale-fathom` |
| `ocaml` | 1 | `v1-skill-ocaml-coq-toolchain` |
| `opam` | 1 | `granite-beacon` |
| `openjdk-17-jre-headless` | 1 | `echo-mantle` |
| `openjdk-21-jre-headless` | 1 | `vine-yonder` |
| `poppler-utils` | 1 | `brisk-anchor` |
| `protobuf-compiler` | 1 | `windlass-jetty` |
| `python3-bs4` | 1 | `fern-hearth` |
| `python3-flask` | 1 | `sage-canyon` |
| `python3-numpy` | 1 | `arid-orchid` |
| `python3-pil` | 1 | `arid-orchid` |
| `python3-psycopg2` | 1 | `keelson-buoy` |
| `python3-sympy` | 1 | `willow-wharf` |
| `r-cran-data.table` | 1 | `gale-meridian` |
| `r-cran-knitr` | 1 | `tundra-jetty` |
| `redis-server` | 1 | `thwart-quarry` |
| `scala` | 1 | `zephyr-summit` |
| `telnet` | 1 | `v1-skill-telnet` |
| `tesseract-ocr-eng` | 1 | `v1-item-025-hard` |
| `texlive-fonts-recommended` | 1 | `willow-wharf` |
| `texlive-latex-base` | 1 | `willow-wharf` |
| `texlive-latex-recommended` | 1 | `willow-wharf` |
| `time` | 1 | `dune-mantle` |
| `tmux` | 1 | `drift-summit` |
| `wget` | 1 | `zephyr-cipher` |
| `xorriso` | 1 | `larch-hearth` |
| `xsltproc` | 1 | `reeve-gate` |
| `xvfb` | 1 | `ingot-flood` |

## Hosts a Dockerfile downloads from

11 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `sh.rustup.rs` | 21 | `alewife-anchorage`, `ballast-anchorage`, `ballast-current`, `bracket-basin`, … |
| `go.dev` | 17 | `ballast-foresheet`, `bollard-inlet`, `bracket-cable`, `bracket-dune`, … |
| `github.com` | 8 | `ballast-chartroom`, `bracket-cairn`, `capstan-inlet`, `cistern-compass`, … |
| `repo.maven.apache.org` | 5 | `ballast-hull`, `capstan-reach`, `hawse-shallows`, `nock-trestle`, … |
| `static.rust-lang.org` | 4 | `bosun-fathom`, `cringle-barquentine`, `cutwater-swell`, `sheer-drift` |
| `archive.apache.org` | 3 | `ballast-caboose`, `capstan-hull`, `deadwood-shoal` |
| `repo.anaconda.com` | 3 | `gale-fathom`, `onyx-ember`, `onyx-gasket` |
| `downloads.claude.ai` | 2 | `basalt-bridge`, `hollow-notch` |
| `raw.githubusercontent.com` | 2 | `bracket-bell`, `cistern-buoy` |
| `alphacephei.com` | 1 | `zephyr-cipher` |
| `releases.hashicorp.com` | 1 | `escutcheon-stack` |

## Task tags

332 distinct entries.

| Skill | Tasks | Example tasks |
|---|---|---|
| `clean-room` | 287 | `alewife-anchorage`, `alewife-dune`, `ballast-anchorage`, `ballast-berm`, … |
| `debugging` | 230 | `alewife-anchorage`, `alewife-dune`, `ballast-anchorage`, `ballast-berm`, … |
| `programming` | 130 | `amber-dial`, `amber-guest`, `amber-ledge`, `amber-quarry`, … |
| `system_administration` | 91 | `amber-upland`, `anchor-quill`, `arid-hearth`, `basalt-bridge`, … |
| `data_processing` | 83 | `alder-crest`, `arid-cipher`, `arid-yonder`, `basalt-buoy`, … |
| `data_science` | 69 | `alder-fathom`, `amber-helix`, `aspen-drift`, `basalt-fjord`, … |
| `security` | 69 | `amber-braid`, `amber-orchid`, `ballast-bollard`, `basalt-fathom`, … |
| `scientific_computing` | 47 | `basalt-dial`, `basalt-mesa`, `basalt-quill`, `basalt-ridge`, … |
| `python` | 36 | `v1-golden-example`, `v1-item-002-hard`, `v1-item-002-main`, `v1-item-003-main`, … |
| `web` | 36 | `amber-cistern`, `amber-engine`, `basalt-maze`, `basalt-quay`, … |
| `binary-re` | 32 | `brine-ridge`, `cinder-dump`, `cinder-fleet`, `cinder-keeper`, … |
| `http-services` | 18 | `anchor-quill`, `basalt-quay`, `brume-delta`, `cinder-reach`, … |
| `ml-inference` | 17 | `alder-fathom`, `basalt-dial`, `basalt-ember`, `clover-anchor`, … |
| `file_operations` | 14 | `cobalt-crate`, `dunlin-key`, `kite-helix`, `maple-vellum`, … |
| `json` | 13 | `v1-golden-example`, `v1-item-049-hard`, `v1-item-063-hard`, `v1-item-063-main`, … |
| `numpy` | 8 | `v1-item-020-main`, `v1-item-037-hard`, `v1-item-037-main`, `v1-item-046-hard`, … |
| `c` | 7 | `v1-item-010-main`, `v1-item-024-main`, `v1-item-031-hard`, `v1-item-031-main`, … |
| `csv` | 6 | `v1-golden-example`, `v1-item-002-hard`, `v1-item-002-main`, `v1-item-039-hard`, … |
| `git` | 6 | `v1-item-026-main`, `v1-item-030-hard`, `v1-item-030-main`, `v1-skill-branch-reset-merge`, … |
| `http` | 6 | `v1-item-050-hard`, `v1-item-059-hard`, `v1-item-059-main`, `v1-skill-http-headers`, … |
| `python-packaging` | 6 | `aster-vellum`, `gray-market`, `quartz-relic`, `sable-mesa`, … |
| `reasoning` | 6 | `bracket-moor`, `cistern-sound`, `ivory-kiln`, `topaz-marsh`, … |
| `cosine-similarity` | 5 | `aurora-reef`, `v1-item-048-main`, `v1-skill-cosine-similarity`, `v1-skill-embeddings`, … |
| `data-processing` | 5 | `drift-mantle`, `pearl-scroll`, `v1-skill-c4-shard-layout`, `v1-skill-dataset-filtering`, … |
| `pytest` | 5 | `v1-item-001-hard`, `v1-item-003-main`, `v1-item-008-hard`, `v1-item-008-main`, … |
| `scientific-computing` | 5 | `copper-stage`, `dune-terrace`, `flint-mantle`, `quartz-delta`, … |
| `sqlite` | 5 | `v1-item-019-main`, `v1-item-062-hard`, `v1-item-062-main`, `v1-skill-explain-query-plan`, … |
| `c-extension` | 4 | `v1-item-056-hard`, `v1-item-056-main`, `v1-skill-c-extension`, `v1-skill-numpy-c-api` |
| `causal-intervention` | 4 | `moss-graph`, `v1-item-002-hard`, `v1-item-002-main`, `v1-skill-causal-intervention` |
| `data-integrity` | 4 | `cobalt-crate`, `coral-ledger`, `jade-shard`, `opal-latch` |
| `item-skill-bucket-18` | 4 | `v1-skill-qemu`, `v1-skill-qemu-5-2`, `v1-skill-query-filtering-aggregation`, `v1-skill-queue-scheduling` |
| `linear-algebra` | 4 | `iron-lattice`, `v1-item-045-hard`, `v1-item-045-main`, `v1-skill-linear-algebra` |
| `nginx` | 4 | `v1-item-034-hard`, `v1-item-034-main`, `v1-item-050-hard`, `v1-skill-nginx` |
| `python-c-api` | 4 | `v1-item-056-hard`, `v1-item-056-main`, `v1-skill-numpy-c-api`, `v1-skill-python-c-api` |
| `adaptive-rejection-sampling` | 3 | `basalt-quill`, `v1-item-001-hard`, `v1-skill-adaptive-rejection-sampling` |
| `asyncio` | 3 | `hazel-forge`, `sable-journal`, `v1-skill-python-asyncio` |
| `asyncio-task-cancellation` | 3 | `v1-item-008-hard`, `v1-item-008-main`, `v1-skill-asyncio-task-cancellation` |
| `aws-github-token-patterns` | 3 | `v1-item-030-hard`, `v1-item-030-main`, `v1-skill-aws-github-token-patterns` |
| `bayesian-network-structure-learning` | 3 | `v1-item-002-hard`, `v1-item-002-main`, `v1-skill-bayesian-network-structure-learning` |
| `benchmarking` | 3 | `v1-item-056-hard`, `v1-item-056-main`, `v1-skill-benchmarking` |
| `build-wheel-metadata` | 3 | `v1-item-059-hard`, `v1-item-059-main`, `v1-skill-build-wheel-metadata` |
| `c-cross-compilation` | 3 | `v1-item-041-hard`, `v1-item-041-main`, `v1-skill-c-cross-compilation` |
| `cifar-10` | 3 | `v1-item-007-hard`, `v1-item-007-main`, `v1-skill-cifar-10` |
| `client-copy-load` | 3 | `flint-terrace`, `pumice-berth`, `quay-ledger` |
| `cpu-training` | 3 | `aspen-drift`, `opal-grove`, `saffron-ember` |
| `cuda-free-cpu-build` | 3 | `v1-item-007-hard`, `v1-item-007-main`, `v1-skill-cuda-free-cpu-build` |
| `dag-fitting` | 3 | `v1-item-002-hard`, `v1-item-002-main`, `v1-skill-dag-fitting` |
| `dataset-filtering` | 3 | `v1-item-016-hard`, `v1-item-016-main`, `v1-skill-dataset-filtering` |
| `deepseek-tokenization` | 3 | `v1-item-016-hard`, `v1-item-016-main`, `v1-skill-deepseek-tokenization` |
| `embeddings` | 3 | `v1-item-048-main`, `v1-skill-embeddings`, `v1-skill-fasttext` |
| `emit-plan-records-schema` | 3 | `basalt-quay`, `cinder-vale`, `flint-ember` |
| `explain-query-plan` | 3 | `v1-item-062-hard`, `v1-item-062-main`, `v1-skill-explain-query-plan` |
| `file-carving` | 3 | `v1-item-053-hard`, `v1-item-053-main`, `v1-skill-file-carving` |
| `filename-date-parsing` | 3 | `v1-item-039-hard`, `v1-item-039-main`, `v1-skill-filename-date-parsing` |
| `finite-differences` | 3 | `v1-item-045-hard`, `v1-item-045-main`, `v1-skill-finite-differences` |
| `git-object-database` | 3 | `v1-item-030-hard`, `v1-item-030-main`, `v1-skill-dangling-commits` |
| `html-parsing` | 3 | `glass-reef`, `v1-item-003-main`, `v1-skill-html-parsing` |
| `huggingface` | 3 | `v1-skill-hugging-face-model-identifiers`, `v1-skill-hugging-face-revision-pinning`, `v1-skill-hugging-face-transformers` |
| `javascript` | 3 | `v1-skill-browser-behavior`, `v1-skill-javascript-xss`, `v1-skill-node-js` |
| `json-weight-conversion` | 3 | `v1-item-031-hard`, `v1-item-031-main`, `v1-skill-json-weight-conversion` |
| `latency-throughput-accounting` | 3 | `v1-item-038-hard`, `v1-item-038-main`, `v1-skill-latency-throughput-accounting` |
| `list-administration` | 3 | `v1-item-040-hard`, `v1-item-040-main`, `v1-skill-list-administration` |
| `log-aggregation` | 3 | `v1-item-039-hard`, `v1-item-039-main`, `v1-skill-log-aggregation` |
| `lorentzian-curves` | 3 | `v1-item-063-hard`, `v1-item-063-main`, `v1-skill-lorentzian-curves` |
| `mailman-3` | 3 | `v1-item-040-hard`, `v1-item-040-main`, `v1-skill-mailman-3` |
| `memory-register-emulation` | 3 | `v1-item-042-hard`, `v1-item-042-main`, `v1-skill-memory-register-emulation` |
| `mips-elf` | 3 | `v1-item-041-hard`, `v1-item-041-main`, `v1-skill-mips-elf` |
| `mips-instruction-set` | 3 | `v1-item-042-hard`, `v1-item-042-main`, `v1-skill-mips-instruction-set` |
| `mnist-inference` | 3 | `v1-item-031-hard`, `v1-item-031-main`, `v1-skill-mnist-inference` |
| `neural-network-inference` | 3 | `v1-item-031-hard`, `v1-item-031-main`, `v1-skill-neural-network-inference` |
| `numpy-arrays` | 3 | `v1-item-056-hard`, `v1-item-056-main`, `v1-skill-numpy-arrays` |
| `optimization` | 3 | `v1-item-015-main`, `v1-skill-numpy-scipy-optimization`, `v1-skill-optimization` |
| `parsing` | 3 | `v1-skill-debian-source-packages`, `v1-skill-fen`, `v1-skill-json` |
| `password-auth` | 3 | `dune-marsh`, `mist-quay`, `vine-helix` |
| `pinned-toolchain-preservation` | 3 | `crisp-relay`, `marble-hearth`, `opal-basin` |
| `postfix` | 3 | `v1-item-040-hard`, `v1-item-040-main`, `v1-skill-postfix` |
| `protobuf-opencv-blas` | 3 | `v1-item-007-hard`, `v1-item-007-main`, `v1-skill-protobuf-opencv-blas` |
| `protocol-buffers` | 3 | `v1-item-035-hard`, `v1-item-035-main`, `v1-skill-protocol-buffers` |
| `python-asyncio` | 3 | `v1-item-008-hard`, `v1-item-008-main`, `v1-skill-python-asyncio` |
| `qemu` | 3 | `v1-item-034-hard`, `v1-item-034-main`, `v1-skill-qemu` |
| `queue-scheduling` | 3 | `v1-item-038-hard`, `v1-item-038-main`, `v1-skill-queue-scheduling` |
| `raman-spectroscopy` | 3 | `v1-item-063-hard`, `v1-item-063-main`, `v1-skill-raman-spectroscopy` |
| `rate-limiting` | 3 | `tundra-bridge`, `v1-item-050-hard`, `v1-skill-rate-limiting` |
| `reverse-engineering` | 3 | `dusk-lattice`, `onyx-mural`, `sable-ray` |
| `rl-policy-training` | 3 | `harbor-keystone`, `kite-mesa`, `quartz-summit` |
| `secret-scanning` | 3 | `v1-item-030-hard`, `v1-item-030-main`, `v1-skill-secret-scanning` |
| `setuptools` | 3 | `v1-item-056-hard`, `v1-skill-c-c-extension-build`, `v1-skill-setuptools` |
| `sql-query-plans` | 3 | `v1-item-062-hard`, `v1-item-062-main`, `v1-skill-sql-query-plans` |
| `sqlite-consistency-checks` | 3 | `v1-item-019-main`, `v1-item-069-hard`, `v1-skill-sqlite-consistency-checks` |
| `sqlite-page-format` | 3 | `v1-item-069-hard`, `v1-item-069-main`, `v1-skill-sqlite-page-format` |
| `sqrt-wasserstein` | 3 | `basalt-fjord`, `iris-terrace`, `quill-anchor` |
| `terminal-escape-sequences` | 3 | `v1-item-032-hard`, `v1-item-032-main`, `v1-skill-terminal-escape-sequences` |
| `tokenizers` | 3 | `v1-item-033-hard`, `v1-skill-deepseek-tokenization`, `v1-skill-tokenizers` |
| `truncated-sqlite-salvage` | 3 | `chert-quay`, `copper-vane`, `flint-terrace` |
| `validation` | 3 | `golden-braid`, `pewter-meridian`, `quartz-upland` |
| `access-log-formats` | 2 | `v1-item-050-hard`, `v1-skill-access-log-formats` |
| `accuracy-window` | 2 | `fen-lantern`, `sable-prism` |
| `alert-schema` | 2 | `juniper-hollow`, `lichen-tide` |
| `arc-agi-data-formats` | 2 | `v1-item-044-main`, `v1-skill-arc-agi-data-formats` |
| `async-context-manager-cleanup` | 2 | `v1-item-008-hard`, `v1-item-008-main` |
| `async-process-io` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `b-tree-records` | 2 | `v1-item-069-main`, `v1-skill-b-tree-records` |
| `binary-parsing` | 2 | `quiet-bridge`, `v1-skill-binary-parsing` |
| `binary-truncation-recovery` | 2 | `v1-item-069-hard`, `v1-item-069-main` |
| `biopython` | 2 | `v1-item-021-main`, `v1-skill-biopython` |
| `bit-byte-streams` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `bit-level-circuits` | 2 | `v1-item-010-main`, `v1-skill-bit-level-circuits` |
| `bitwise-arithmetic` | 2 | `v1-item-024-main`, `v1-skill-bitwise-arithmetic` |
| `black-box-neural-network-queries` | 2 | `v1-item-045-hard`, `v1-item-045-main` |
| `bounding-box-filter` | 2 | `gull-radar`, `heath-signal` |
| `bring-up-a-multi-process-system` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `browser-behavior` | 2 | `v1-item-003-main`, `v1-skill-browser-behavior` |
| `build-and-install-software-from-source` | 2 | `kite-anchor`, `onyx-gasket` |
| `byte-cap` | 2 | `opal-marsh`, `pewter-hull` |
| `c-reverse-engineering` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `caffe-1.0` | 2 | `v1-item-007-hard`, `v1-item-007-main` |
| `canonical-config` | 2 | `bryony-keep`, `wren-spire` |
| `check-service-reachability-and-versions` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `circular-sequence-boundaries` | 2 | `v1-item-021-main`, `v1-skill-circular-sequence-boundaries` |
| `cli-abi` | 2 | `v1-item-031-hard`, `v1-item-031-main` |
| `climate-data-formats` | 2 | `v1-item-046-hard`, `v1-skill-climate-data-formats` |
| `code-size-optimization` | 2 | `v1-item-031-hard`, `v1-item-031-main` |
| `compatibility-migration` | 2 | `v1-item-046-hard`, `v1-skill-compatibility-migration` |
| `complex-values` | 2 | `v1-item-037-hard`, `v1-item-037-main` |
| `compose-credentials` | 2 | `granary-ledge`, `moor-atlas` |
| `compression-formats` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `computed-payload` | 2 | `cypress-lantern`, `spume-ferry` |
| `concurrent-server-state` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `conflict-report` | 2 | `copper-thicket`, `glass-forge` |
| `constraint-satisfaction` | 2 | `v1-item-015-main`, `v1-skill-constraint-satisfaction` |
| `cpp` | 2 | `v1-item-007-hard`, `v1-item-007-main` |
| `crypto` | 2 | `v1-skill-feal-like-cipher`, `v1-skill-feal-like-round-functions` |
| `csv-join` | 2 | `hazel-quay`, `opal-summit` |
| `custom-decompressor` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `cwe-93-crlf-injection` | 2 | `v1-item-026-main`, `v1-skill-cwe-93-crlf-injection` |
| `cwe-mapping` | 2 | `cinder-forge`, `gale-slate` |
| `cython-numpy2-build-compat` | 2 | `basalt-mantle`, `moss-latch` |
| `dag-structure-learning` | 2 | `coral-trellis`, `umbral-mesh` |
| `dangling-commits` | 2 | `v1-item-027-main`, `v1-skill-dangling-commits` |
| `decode-serialized-preference-fixtures-in-multiple-encodings` | 2 | `arid-yonder`, `garnet-mesa` |
| `default-interpreter-package-repair` | 2 | `basalt-mantle`, `onyx-ember` |
| `define-the-wire-contract-first` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `deleted-file-recovery` | 2 | `cinder-loom`, `ember-quill` |
| `derived-statistics` | 2 | `cinder-reach`, `cobalt-fjord` |
| `descriptor-proximity-ranking` | 2 | `umber-prism`, `zinc-meridian` |
| `digital-forensics` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `disk-images` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `dom-sanitization` | 2 | `v1-item-003-main`, `v1-skill-dom-sanitization` |
| `doom-generic` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `dynamic-programming` | 2 | `v1-skill-dag-fitting`, `v1-skill-fibonacci` |
| `eigenvalue-eigenvector-numerics` | 2 | `v1-item-037-hard`, `v1-item-037-main` |
| `elf-loading` | 2 | `v1-item-042-hard`, `v1-item-042-main` |
| `endianness` | 2 | `quiet-bridge`, `v1-skill-host-abi-and-architecture` |
| `expose-required-entry-point-functions-under-required-names` | 2 | `saffron-dial`, `willow-wharf` |
| `extract-and-persist-the-integer-part-of-the-objective` | 2 | `gale-keystone`, `sable-orbit` |
| `fasta` | 2 | `v1-item-021-main`, `v1-skill-fasta` |
| `fasttext-classifier` | 2 | `cobalt-sonar`, `iris-crate` |
| `feal-like-cipher` | 2 | `v1-item-024-main`, `v1-skill-feal-like-cipher` |
| `feal-like-round-functions` | 2 | `v1-item-024-main`, `v1-skill-feal-like-round-functions` |
| `fibonacci-arithmetic` | 2 | `v1-item-010-main`, `v1-skill-fibonacci-arithmetic` |
| `filesystem-moves` | 2 | `v1-item-025-hard`, `v1-skill-filesystem-moves` |
| `filesystem-traversal` | 2 | `v1-item-068-main`, `v1-skill-filesystem-traversal` |
| `fine-tuning-script` | 2 | `quill-fathom`, `saffron-ember` |
| `flask` | 2 | `v1-item-033-hard`, `v1-skill-flask` |
| `fluorescent-proteins` | 2 | `v1-item-057-main`, `v1-skill-fluorescent-proteins` |
| `format-constraint-enumeration` | 2 | `sorrel-tide`, `zephyr-engine` |
| `fragment-reassembly` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `fret-spectra` | 2 | `v1-item-057-main`, `v1-skill-fret-spectra` |
| `greedy-sequence-generation` | 2 | `cedar-vault`, `vine-pier` |
| `grid-expansion` | 2 | `kiln-vane`, `prism-pier` |
| `grpc` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `grpcio-grpcio-tools` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `handle-lifecycle-and-repeat-requests` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `handle-timing-and-partial-reads` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `hex-strings-tools` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `history-rewriting` | 2 | `v1-item-030-hard`, `v1-item-030-main` |
| `http-headers` | 2 | `v1-item-026-main`, `v1-skill-http-headers` |
| `http-json-api` | 2 | `v1-item-033-hard`, `v1-skill-http-json-api` |
| `hugging-face-datasets` | 2 | `v1-item-016-hard`, `v1-item-016-main` |
| `hugging-face-model-identifiers` | 2 | `v1-item-047-main`, `v1-skill-hugging-face-model-identifiers` |
| `hugging-face-revision-pinning` | 2 | `v1-item-048-main`, `v1-skill-hugging-face-revision-pinning` |
| `hugging-face-transformers` | 2 | `v1-item-033-hard`, `v1-skill-hugging-face-transformers` |
| `image-normalization` | 2 | `v1-item-031-hard`, `v1-item-031-main` |
| `implement-an-integer-mathematical-function-as-a-finite-logic-gate-network` | 2 | `kite-summit`, `wren-vane` |
| `import-api` | 2 | `quartz-relic`, `sable-mesa` |
| `indexes` | 2 | `v1-item-062-hard`, `v1-item-062-main` |
| `install-from-local-index` | 2 | `elm-ridge`, `gale-fathom` |
| `interactive-bash` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `invalid-and-unmatched-pair-exclusion` | 2 | `cinder-dial`, `copper-quill` |
| `item-002` | 2 | `v1-item-002-hard`, `v1-item-002-main` |
| `item-007` | 2 | `v1-item-007-hard`, `v1-item-007-main` |
| `item-008` | 2 | `v1-item-008-hard`, `v1-item-008-main` |
| `item-016` | 2 | `v1-item-016-hard`, `v1-item-016-main` |
| `item-030` | 2 | `v1-item-030-hard`, `v1-item-030-main` |
| `item-031` | 2 | `v1-item-031-hard`, `v1-item-031-main` |
| `item-032` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `item-034` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `item-035` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `item-037` | 2 | `v1-item-037-hard`, `v1-item-037-main` |
| `item-038` | 2 | `v1-item-038-hard`, `v1-item-038-main` |
| `item-039` | 2 | `v1-item-039-hard`, `v1-item-039-main` |
| `item-040` | 2 | `v1-item-040-hard`, `v1-item-040-main` |
| `item-041` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `item-042` | 2 | `v1-item-042-hard`, `v1-item-042-main` |
| `item-045` | 2 | `v1-item-045-hard`, `v1-item-045-main` |
| `item-053` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `item-056` | 2 | `v1-item-056-hard`, `v1-item-056-main` |
| `item-057` | 2 | `v1-item-057-hard`, `v1-item-057-main` |
| `item-059` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `item-062` | 2 | `v1-item-062-hard`, `v1-item-062-main` |
| `item-063` | 2 | `v1-item-063-hard`, `v1-item-063-main` |
| `item-068` | 2 | `v1-item-068-hard`, `v1-item-068-main` |
| `item-069` | 2 | `v1-item-069-hard`, `v1-item-069-main` |
| `item-076` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `javascript-node-js` | 2 | `v1-item-042-hard`, `v1-item-042-main` |
| `javascript-xss` | 2 | `v1-item-003-main`, `v1-skill-javascript-xss` |
| `json-reconciliation` | 2 | `cobalt-wharf`, `sable-heron` |
| `jupyter-server-config` | 2 | `pale-heron`, `quiet-loom` |
| `linear-cryptanalysis` | 2 | `v1-item-024-main`, `v1-skill-linear-cryptanalysis` |
| `lm-eval-harness-wiring` | 2 | `sable-prism`, `sable-vellum` |
| `locale-filter-jsonl-export` | 2 | `opal-lantern`, `saffron-loom` |
| `log-concavity` | 2 | `v1-item-001-hard`, `v1-skill-log-concavity` |
| `log-triage` | 2 | `juniper-hollow`, `lichen-tide` |
| `logic-gate-netlists` | 2 | `v1-item-010-main`, `v1-skill-logic-gate-netlists` |
| `mailing-lists` | 2 | `bryony-keep`, `wren-spire` |
| `make` | 2 | `v1-item-041-hard`, `v1-item-041-main` |
| `mips` | 2 | `v1-skill-mips-elf`, `v1-skill-mips-instruction-set` |
| `mlp-classifier` | 2 | `basalt-ember`, `orchid-model` |
| `model-an-interactive-state-machine` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `model-init-adequacy` | 2 | `gale-ridge`, `quartz-marsh` |
| `model-size-budget` | 2 | `cobalt-sonar`, `dusk-forge` |
| `mteb-leaderboard` | 2 | `v1-item-047-main`, `v1-skill-mteb-leaderboard` |
| `mujoco-plugin-free-tuning` | 2 | `drift-atlas`, `myrtle-canyon` |
| `multi-source-reconciliation` | 2 | `black-ink`, `brine-cistern` |
| `multi-step-digest` | 2 | `basalt-fathom`, `sage-wharf` |
| `multiple-choice-classification` | 2 | `fen-lantern`, `sable-prism` |
| `ncbi-rcsb-apis` | 2 | `v1-item-057-main`, `v1-skill-ncbi-rcsb-apis` |
| `neural-net` | 2 | `v1-skill-mnist-inference`, `v1-skill-neural-network-inference` |
| `normalized-2d-histogram` | 2 | `gull-radar`, `heath-signal` |
| `numpy-scipy-optimization` | 2 | `v1-item-063-hard`, `v1-item-063-main` |
| `offline-model-load` | 2 | `marble-hearth`, `opal-basin` |
| `ontology-traversal` | 2 | `v1-item-068-hard`, `v1-skill-ontology-traversal` |
| `open-english-wordnet-schema` | 2 | `v1-item-062-hard`, `v1-item-062-main` |
| `openmp` | 2 | `gale-quarry`, `kite-yonder` |
| `osmesa-library-loading` | 2 | `basalt-mantle`, `onyx-gasket` |
| `pandas` | 2 | `v1-item-002-hard`, `v1-item-002-main` |
| `parse-cli-args-and-write-documented-output-formats` | 2 | `frost-latch`, `kite-anchor` |
| `pep-503-package-index` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `per-line-defect-repair` | 2 | `sable-wicket`, `wren-quarry` |
| `period-filter` | 2 | `hazel-quay`, `opal-summit` |
| `pickle-model-persist` | 2 | `saffron-mesa`, `vine-pier` |
| `pinned-version-preservation` | 2 | `frost-quay`, `vine-ledge` |
| `pip-index-url` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `placeholder-substitution` | 2 | `v1-item-030-hard`, `v1-item-030-main` |
| `png` | 2 | `v1-item-009-main`, `v1-skill-file-carving` |
| `point-binning` | 2 | `gull-radar`, `heath-signal` |
| `portfolio-risk-return-math` | 2 | `v1-item-056-hard`, `v1-item-056-main` |
| `postgres` | 2 | `granary-ledge`, `moor-atlas` |
| `power-iteration-or-lapack` | 2 | `v1-item-037-hard`, `v1-item-037-main` |
| `prescribed-schema` | 2 | `flint-terrace`, `quay-ledger` |
| `preserve-evidence` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `probability-distributions` | 2 | `v1-item-020-main`, `v1-skill-probability-distributions` |
| `protein-engineering` | 2 | `v1-item-057-main`, `v1-skill-protein-engineering` |
| `ptys` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `pypiserver` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `python-or-c-binary-i-o` | 2 | `v1-item-019-main`, `v1-item-069-hard` |
| `pytorch` | 2 | `v1-skill-torch-distributed`, `v1-skill-torch-serialization` |
| `query-filtering-aggregation` | 2 | `v1-item-068-hard`, `v1-skill-query-filtering-aggregation` |
| `qwen2.5-tokenizer` | 2 | `v1-item-016-hard`, `v1-item-016-main` |
| `r-runtime-availability` | 2 | `basalt-mantle`, `bracken-river` |
| `rdf-engine` | 2 | `v1-item-068-hard`, `v1-skill-rdf-engine` |
| `rdf-turtle` | 2 | `v1-item-068-hard`, `v1-skill-rdf-turtle` |
| `record-reconciliation` | 2 | `copper-thicket`, `glass-forge` |
| `reflog-fsck` | 2 | `v1-item-030-hard`, `v1-item-030-main` |
| `regex` | 2 | `v1-skill-lexer-parser-compatibility`, `v1-skill-text-processing` |
| `regex-escaping` | 2 | `v1-item-003-main`, `v1-skill-regex-escaping` |
| `relu-mlp-interrogation` | 2 | `mica-marsh`, `tundra-ledge` |
| `relu-piecewise-linear-analysis` | 2 | `v1-item-045-hard`, `v1-item-045-main` |
| `repository-hygiene` | 2 | `v1-item-030-hard`, `v1-item-030-main` |
| `revenue-ranking` | 2 | `hazel-quay`, `opal-summit` |
| `reverse-complements` | 2 | `v1-item-021-main`, `v1-skill-reverse-complements` |
| `rms-normalization` | 2 | `opal-quill`, `opal-wave` |
| `rooted-transport-distance` | 2 | `basalt-fjord`, `quill-anchor` |
| `round-accuracy-scoring` | 2 | `cinder-dial`, `copper-quill` |
| `scalar-product` | 2 | `aster-vellum`, `sable-mesa` |
| `scaling` | 2 | `quartz-haven`, `v1-skill-model-size-accuracy-tradeoff` |
| `schema-reconciliation` | 2 | `v1-item-049-hard`, `v1-skill-schema-reconciliation` |
| `scipy` | 2 | `v1-skill-numpy-scipy-optimization`, `v1-skill-optimization` |
| `self-test-reporting` | 2 | `drift-terrace`, `tundra-bridge` |
| `semaphores-concurrency-limits` | 2 | `v1-item-008-hard`, `v1-item-008-main` |
| `serial-console` | 2 | `v1-item-061-hard`, `v1-skill-serial-console` |
| `shape-aware-batching` | 2 | `v1-item-038-hard`, `v1-skill-shape-aware-batching` |
| `single-byte-xor-wal-recovery` | 2 | `brine-cipher`, `rust-quay` |
| `single-node-cluster` | 2 | `drift-marsh`, `sorrel-quay` |
| `smtp` | 2 | `v1-item-040-hard`, `v1-item-040-main` |
| `solver-configuration` | 2 | `v1-item-007-hard`, `v1-item-007-main` |
| `speculative-draft-verify` | 2 | `kestrel-loop`, `vine-pier` |
| `static-analysis` | 2 | `cinder-forge`, `gale-slate` |
| `stdin-stdout` | 2 | `v1-item-076-hard`, `v1-item-076-main` |
| `streaming-inference` | 2 | `coral-basin`, `vine-forge` |
| `sudoku-solver` | 2 | `mica-grid`, `vine-delta` |
| `syscalls` | 2 | `v1-item-042-hard`, `v1-item-042-main` |
| `systemd-processes` | 2 | `v1-item-040-hard`, `v1-item-040-main` |
| `test-a-live-server-with-a-real-client` | 2 | `v1-item-035-hard`, `v1-item-035-main` |
| `test-install-from-clean-environment` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `test-suite-target-pass-count` | 2 | `gale-ledge`, `prism-anchor` |
| `test-user-visible-behavior` | 2 | `v1-item-032-hard`, `v1-item-032-main` |
| `tex-log-diagnostics` | 2 | `v1-item-052-main`, `v1-skill-tex-log-diagnostics` |
| `timezone-date-ranges` | 2 | `v1-item-039-hard`, `v1-item-039-main` |
| `top-k-ranking` | 2 | `drift-pier`, `larch-jetty` |
| `trained-model-snapshot` | 2 | `tide-grove`, `topaz-quarry` |
| `transfer-rule` | 2 | `drift-pier`, `granite-grove` |
| `upstream-bugfix` | 2 | `cistern-fathom`, `cistern-forge` |
| `valgrind` | 2 | `cobalt-marlin`, `harbor-notch` |
| `validate-packaging-separately-from-serving` | 2 | `v1-item-059-hard`, `v1-item-059-main` |
| `validate-recovered-content` | 2 | `v1-item-053-hard`, `v1-item-053-main` |
| `value-iteration` | 2 | `harbor-keystone`, `kite-mesa` |
| `venv-install-pinned-package` | 2 | `elm-ridge`, `gale-fathom` |
| `verify-keyboard-input-paths-end-to-end` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `verify-pip-install` | 2 | `elm-ridge`, `gale-fathom` |
| `vnc` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `vocabulary-construction` | 2 | `hazel-quarry`, `mica-fjord` |
| `wait-on-real-readiness-signals` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `wal-replay` | 2 | `flint-terrace`, `kiln-journal` |
| `wal-transform-detection` | 2 | `calm-bridge`, `sage-wharf` |
| `web-research` | 2 | `v1-item-047-main`, `v1-skill-web-research` |
| `websockify-novnc` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `windows-3.11` | 2 | `v1-item-034-hard`, `v1-item-034-main` |
| `wsgi` | 2 | `quartz-haven`, `velvet-ember` |
| `xor-uint32-arithmetic` | 2 | `v1-item-024-main`, `v1-skill-xor-uint32-arithmetic` |
| `xss` | 2 | `v1-skill-dom-sanitization`, `v1-skill-javascript-xss` |
| `xss-defenses` | 2 | `v1-item-003-main`, `v1-skill-xss-defenses` |
